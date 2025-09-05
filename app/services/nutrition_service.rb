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
  # Find the ingredient only if it exists and has nutritional data (calories > 0)
    ingredient = Ingredient.where(
    ingredient_name: ingredient_name.downcase.strip).where("calories_per_gram > 0").first

    # If an ingredient with valid data doesn't exist, proceed to create one
    unless ingredient
      nutrition_data = fetch_nutrition_data(ingredient_name, quantity, unit)

      if nutrition_data && nutrition_data['foods'].present?
        food = nutrition_data['foods'].first
        total_calories = food['nf_calories']
        total_protein = food['nf_protein']
        total_fat = food['nf_total_fat']
        total_carbs = food['nf_total_carbohydrate']

        # Create the ingredient in the database
        ingredient = Ingredient.create!(
          ingredient_name: food['food_name'].downcase,
          calories_per_gram: total_calories / food['serving_weight_grams'].round(2),
          protein_per_gram: total_protein / food['serving_weight_grams'].round(2),
          carbs_per_gram: total_carbs / food['serving_weight_grams'].round(2),
          fat_per_gram: total_fat / food['serving_weight_grams'].round(2),
          serving_weight_grams: food['serving_weight_grams'].round(2)
        )
      else
        # If no data found from API, create a default ingredient with no nutritional data
        ingredient = Ingredient.create!(
          ingredient_name: ingredient_name, calories_per_gram: 0, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 0, serving_weight_grams: 0)
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

  # Helper method to convert unit to grams
  def get_grams_for_unit(unit)
    case unit.downcase
    when 'cup'
      250.0
    when 'tablespoon'
      15.0
    when 'teaspoon'
      5.0
    when 'g', 'gram', 'grams'
      1.0
    when 'lb', 'pound', 'pounds'
      453.592
    when 'oz', 'ounce', 'ounces'
      28.3495
    else
      0.0
    end
  end
end
