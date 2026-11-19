class NutritionService
  BASE_URL = "https://trackapi.nutritionix.com/v2"
  HEADERS = {
    "Content-Type" => "application/json"
  }
  NUTRIENT_FIELDS = {
    calories: "nf_calories", protein: "nf_protein",
    carbs: "nf_total_carbohydrate", fat: "nf_total_fat"
  }.freeze

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

    ingredient = Ingredient.find_or_initialize_by(ingredient_name: ingredient_name)
    unless nutrition_available?(ingredient)
      nutrition_data = fetch_nutrition_data(ingredient_name, quantity, unit)
      food = nutrition_data["foods"].first if nutrition_data.is_a?(Hash) && nutrition_data["foods"].is_a?(Array)
      weight = food["serving_weight_grams"] if food.is_a?(Hash)
      available = nonnegative_number?(weight) && weight.positive? &&
        NUTRIENT_FIELDS.values.all? { |field| nonnegative_number?(food[field]) && (food[field].to_f / weight).finite? }
      attributes = NUTRIENT_FIELDS.to_h do |nutrient, field|
        ["#{nutrient}_per_gram", available ? food[field].to_f / weight : nil]
      end
      ingredient.update!(attributes.merge("serving_weight_grams" => available ? weight : nil))
    end

    ingredient
  end

  def update_recipe_nutrition(recipe, servings: 1)
    totals = { total_calories: 0, total_protein: 0, total_carbs: 0, total_fat: 0 }
    recipe.recipe_ingredients.each do |ri|
      nutrition = ingredient_nutrition(ri)
      return unavailable_nutrition unless nutrition[:nutrition_available]

      totals.each_key { |nutrient| totals[nutrient] += nutrition[nutrient] * servings }
    end
    totals.transform_values { |value| value.round(2) }.merge(nutrition_available: true)
  end

  def ingredient_nutrition(recipe_ingredient)
    ingredient = recipe_ingredient.ingredient
    grams_per_unit = get_grams_for_unit(recipe_ingredient.unit)
    quantity = Float(recipe_ingredient.quantity, exception: false)
    return unavailable_nutrition unless nutrition_available?(ingredient) && grams_per_unit &&
      nonnegative_number?(quantity) && quantity.positive?

    grams = grams_per_unit * quantity
    totals = NUTRIENT_FIELDS.keys.to_h do |nutrient|
      ["total_#{nutrient}".to_sym, ingredient.public_send("#{nutrient}_per_gram") * grams]
    end
    return unavailable_nutrition unless totals.values.all?(&:finite?)

    totals.merge(nutrition_available: true)
  end

  def get_grams_for_unit(unit)
    case unit.to_s.downcase.strip
    when 'g', 'gram', 'grams'
      1.0
    when 'kg', 'kilogram', 'kilograms'  
      1000.0
    when 'lb', 'pound', 'pounds'
      453.59
    when 'oz', 'ounce', 'ounces'
      28.35
    else
      nil
    end
  end

  private

  def nutrition_available?(ingredient)
    ingredient && nonnegative_number?(ingredient.serving_weight_grams) && ingredient.serving_weight_grams.positive? &&
      NUTRIENT_FIELDS.keys.all? { |nutrient| nonnegative_number?(ingredient.public_send("#{nutrient}_per_gram")) }
  end

  def nonnegative_number?(value)
    value.is_a?(Numeric) && value.finite? && value >= 0
  end

  def unavailable_nutrition
    { total_calories: nil, total_protein: nil, total_carbs: nil, total_fat: nil, nutrition_available: false }
  end
end
