class NutritionService
  BASE_URL = "https://trackapi.nutritionix.com/v2"
  HEADERS = {
    "Content-Type" => "application/json"
  }

  def initialize
    @credentials = Rails.application.credentials.nutritionix
    @headers = HEADERS.merge(
      "x-app-id" => @credentials[:app_id],
      "x-app-key" => @credentials[:app_key]
    )
  end

  # Fetch nutrition data from the Nutritionix API
  def fetch_nutrition_data(query, quantity, unit)
    formatted_query = "#{quantity} #{unit} of #{query}"
    Rails.logger.info "Nutritionix API Request: #{formatted_query}"
    
    begin
      response = HTTParty.post(
        "#{BASE_URL}/natural/nutrients",
        headers: @headers,
        body: { query: formatted_query }.to_json
      )
      
      Rails.logger.info "Nutritionix API Response Status: #{response.code}"
      Rails.logger.info "Nutritionix API Response Body: #{response.body}"
      
      if response.success?
        response.parsed_response
      else
        Rails.logger.error "Nutritionix API Error: #{response.code} - #{response.body}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "Error fetching data from Nutritionix API: #{e.message}"
      nil
    end
  end

  # Find or create an ingredient based on data
  def find_or_create_ingredient(ingredient_name, quantity, unit)
    ingredient_name = ingredient_name.downcase.strip

    # Try to find existing ingredient by name, regardless of calories
    ingredient = Ingredient.find_or_initialize_by(ingredient_name: ingredient_name)

    # Only fetch and update nutritional data if calories are not set
    if ingredient.calories_per_gram.to_f <= 0
      nutrition_data = fetch_nutrition_data(ingredient_name, quantity, unit)

      if nutrition_data && nutrition_data['foods'].present?
        food = nutrition_data['foods'].first
        total_calories = food['nf_calories']
        total_protein = food['nf_protein']
        total_fat = food['nf_total_fat']
        total_carbs = food['nf_total_carbohydrate']

        ingredient.update!(
          calories_per_gram: total_calories / food['serving_weight_grams'].round(2),
          protein_per_gram: total_protein / food['serving_weight_grams'].round(2),
          carbs_per_gram: total_carbs / food['serving_weight_grams'].round(2),
          fat_per_gram: total_fat / food['serving_weight_grams'].round(2),
          serving_weight_grams: food['serving_weight_grams'].round(2)
        )
      else
        # Default ingredient if no API data
        ingredient.update!(
          calories_per_gram: 0,
          protein_per_gram: 0,
          carbs_per_gram: 0,
          fat_per_gram: 0,
          serving_weight_grams: 0
        )
      end
    end

    ingredient
  end

  # Update recipe nutrition based on recipe ingredients
  def update_recipe_nutrition(recipe)
    total_calories = 0
    total_protein = 0
    total_carbs = 0
    total_fat = 0

    recipe.recipe_ingredients.each do |ri|
      ingredient = ri.ingredient
      next unless ingredient

      total_grams = get_grams_for_unit(ri.unit) * ri.quantity.to_f

      total_calories += (ingredient.calories_per_gram || 0) * total_grams
      total_protein += (ingredient.protein_per_gram || 0) * total_grams
      total_carbs += (ingredient.carbs_per_gram || 0) * total_grams
      total_fat += (ingredient.fat_per_gram || 0) * total_grams
    end

    {
      total_calories: total_calories.round(2),
      total_protein: total_protein.round(2),
      total_carbs: total_carbs.round(2),
      total_fat: total_fat.round(2)
    }
  end

  def get_grams_for_unit(unit)
    case unit.downcase.strip
    when 'g', 'gram', 'grams'
      1.0
    when 'kg', 'kilogram', 'kilograms'  
      1000.0
    when 'lb', 'pound', 'pounds'
      453.59
    when 'oz', 'ounce', 'ounces'
      28.35
    when 'cup', 'cups'
      240.0
    when 'tablespoon', 'tbsp'
      15.0
    when 'teaspoon', 'tsp'
      5.0
    when 'ml', 'milliliter'
      1.0
    when 'liter', 'l', 'litre'
      1000.0
    when 'small'
      75.0
    when 'medium'
      100.0
    when 'large'
      150.0
    when 'slice'
      25.0
    when 'piece', 'pc', 'whole'
      100.0
    else
      Rails.logger.warn "Unknown unit: #{unit}"
      100.0  # Safe default
    end
  end
end
