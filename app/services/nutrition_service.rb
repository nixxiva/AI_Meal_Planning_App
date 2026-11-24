class NutritionService
  BASE_URL = "https://trackapi.nutritionix.com/v2"
  HEADERS = {
    "Content-Type" => "application/json"
  }
  NUTRIENT_FIELDS = {
    calories: [ 208, "nf_calories" ], protein: [ 203, "nf_protein" ],
    carbs: [ 205, "nf_total_carbohydrate" ], fat: [ 204, "nf_total_fat" ]
  }.freeze
  TOTAL_KEYS = NUTRIENT_FIELDS.keys.map { |nutrient| :"total_#{nutrient}" }.freeze

  # Fetch nutrition data from the Nutritionix API
  def fetch_nutrition_data(query, quantity, unit)
    credentials = Rails.application.credentials.nutritionix
    headers = HEADERS.merge(
      "x-app-id" => credentials[:app_id],
      "x-app-key" => credentials[:app_key]
    )
    formatted_query = "#{quantity} #{unit} of #{query}"
    Rails.logger.info "Nutritionix API Request: #{formatted_query}"

    begin
      response = HTTParty.post(
        "#{BASE_URL}/natural/nutrients",
        headers: headers,
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
      foods = nutrition_data["foods"] if nutrition_data.is_a?(Hash)
      food = foods.first if foods.is_a?(Array) && foods.length == 1
      weight = food["serving_weight_grams"] if food.is_a?(Hash)
      amounts = provider_nutrients_per_gram(food, weight) if nonnegative_number?(weight) && weight.positive?
      available = amounts && amounts.values.none?(&:nil?)
      attributes = NUTRIENT_FIELDS.keys.to_h do |nutrient|
        [ "#{nutrient}_per_gram", available ? amounts.fetch(nutrient) : nil ]
      end
      ingredient.update!(attributes.merge("serving_weight_grams" => available ? weight : nil))
    end

    ingredient
  end

  def recipe_nutrition(recipe, servings: 1)
    ingredients = recipe.recipe_ingredients.lazy.map { |ingredient| ingredient_nutrition(ingredient) }
    sum_nutrition(ingredients, servings: servings)
  end

  def recipe_ingredient_attributes(name, quantity, unit, previous_line: nil)
    normalized_name = name.downcase.strip
    measure = if previous_line
      previous_line.nutrition_measure
    else
      RecipeIngredientMeasurement.resolve(normalized_name, quantity, unit, mass_grams_per_unit: get_grams_for_unit(unit))
    end
    ingredient = if measure
      previous_line&.ingredient || Ingredient.find_or_create_by!(ingredient_name: normalized_name)
    else
      find_or_create_ingredient(name, quantity, unit)
    end

    { ingredient: ingredient, quantity: quantity, unit: unit, nutrition_measure: measure }
  end

  def sum_nutrition(items, servings: 1)
    totals = TOTAL_KEYS.index_with(0)
    items.each do |item|
      return unavailable_nutrition unless item.fetch(:nutrition_available)

      totals.each_key { |key| totals[key] += item.fetch(key) * servings }
    end
    return unavailable_nutrition unless totals.values.all?(&:finite?)

    totals.merge(nutrition_available: true)
  end

  def rounded_nutrition(nutrition)
    nutrition.transform_values { |value| value.is_a?(Numeric) ? value.round(2) : value }
  end

  def ingredient_nutrition(recipe_ingredient)
    measure = recipe_ingredient.nutrition_measure
    return measure.fetch("totals").symbolize_keys.merge(nutrition_available: true) if measure

    ingredient = recipe_ingredient.ingredient
    grams_per_unit = get_grams_for_unit(recipe_ingredient.unit)
    quantity = Float(recipe_ingredient.quantity, exception: false)
    return unavailable_nutrition unless nutrition_available?(ingredient) && grams_per_unit &&
      nonnegative_number?(quantity) && quantity.positive?

    grams = grams_per_unit * quantity
    totals = NUTRIENT_FIELDS.keys.to_h do |nutrient|
      [ "total_#{nutrient}".to_sym, ingredient.public_send("#{nutrient}_per_gram") * grams ]
    end
    return unavailable_nutrition unless totals.values.all?(&:finite?)

    totals.merge(nutrition_available: true)
  end

  def get_grams_for_unit(unit)
    case unit.to_s.downcase.strip
    when "g", "gram", "grams"
      1.0
    when "kg", "kilogram", "kilograms"
      1000.0
    when "lb", "pound", "pounds"
      453.59
    when "oz", "ounce", "ounces"
      28.35
    else
      nil
    end
  end

  private

  def provider_nutrients_per_gram(food, weight)
    details = food["full_nutrients"]
    details = [] unless details.is_a?(Array)

    NUTRIENT_FIELDS.to_h do |nutrient, (attribute_id, summary_field)|
      matches = details.select { |row| row.is_a?(Hash) && row["attr_id"] == attribute_id }
      detailed_amount = matches.first["value"] if matches.one?
      amount = per_gram(detailed_amount, weight) || per_gram(food[summary_field], weight)
      [ nutrient, amount ]
    end
  end

  def per_gram(amount, weight)
    return unless nonnegative_number?(amount)

    result = amount.to_f / weight
    result if result.finite?
  end

  def nutrition_available?(ingredient)
    ingredient && nonnegative_number?(ingredient.serving_weight_grams) && ingredient.serving_weight_grams.positive? &&
      NUTRIENT_FIELDS.keys.all? { |nutrient| nonnegative_number?(ingredient.public_send("#{nutrient}_per_gram")) }
  end

  def nonnegative_number?(value)
    value.is_a?(Numeric) && value.finite? && value >= 0
  end

  def unavailable_nutrition
    TOTAL_KEYS.index_with(nil).merge(nutrition_available: false)
  end
end
