class MealPlanGeneratorService
  PANTRY_AMOUNT_UNITS = %w[
    mg milligram milligrams g gram grams kg kilogram kilograms oz ounce ounces lb pound pounds
    ml milliliter milliliters l liter liters cup cups fl\ oz fluid\ ounce fluid\ ounces
    teaspoon teaspoons tsp tablespoon tablespoons tbsp
    piece pieces item items count egg eggs can cans
  ].freeze

  def initialize(user)
    @user = user
  end

  # Main method to generate a 1-day meal plan
  def generate_1_day_plan
    preferences = gather_preferences
    ai_response = call_ai_service(preferences)
    meal_plan_data = parse_ai_response(ai_response)
    validate_meal_plan!(meal_plan_data)

    create_meal_plan_in_db(meal_plan_data)
  end

  private

  def gather_preferences
    {
      dietary_preferences: @user.dietary_preferences.pluck(:pref_name),
      allergies: @user.allergies.pluck(:allergy_name),
      disliked_ingredients: @user.disliked_ingredients.pluck(:ingredient_name),
      health_goal: @user.health_goal&.goal_name,
      pantry_items: pantry_guidance,
      recipes: @user.recipes.pluck(:title)
    }
  end

  def pantry_guidance
    @user.pantry_items.pluck(:name, :quantity, :unit).map do |name, quantity, unit|
      unit = unit.to_s.strip
      usable_unit = PANTRY_AMOUNT_UNITS.include?(unit.downcase)
      usable_amount = quantity&.finite? && quantity >= 0 && (usable_unit || quantity.zero?)
      { name: name.to_s.strip, quantity: usable_amount ? quantity : nil, unit: usable_amount && usable_unit ? unit : nil }
    end
  end

  def call_ai_service(preferences)
    prompt = <<~PROMPT
      You are a helpful nutritionist.

      Create a 1-day meal plan for a user with:
      Dietary preferences: #{preferences[:dietary_preferences].join(", ")}
      Allergies: #{preferences[:allergies].join(", ")}
      Disliked ingredients: #{preferences[:disliked_ingredients].join(", ")}
      Health goal: #{preferences[:health_goal]}
      Available pantry items: #{preferences[:pantry_items].to_json}

      Requirements:
        1. Prioritize using pantry items when possible. Pantry amounts are guidance only. When units match, aim to stay within the reported amount across all meals. A zero quantity means that pantry entry is out of stock. A null quantity means the amount is unknown. Do not estimate unknown amounts or combine incompatible units.
        2. Suggest only a few additional ingredients beyond the pantry to make meals balanced and nutritious. Avoid unnecessary spices or minor ingredients unless essential.
        3. Ensure each meal is unique. Use different subsets of pantry items for each meal when possible and avoid repeating recipes listed in #{preferences[:recipes].join(", ")}.
        4. Include diverse main ingredients (vegetables, proteins, grains, etc.) to make each meal distinct.
        5. Feel free to create entirely new dishes or variations of pantry-based dishes as long as they align with the user's preferences.
        6. Provide exactly 3 meals: breakfast, lunch, and dinner. Each recipe should make one suggested portion.
        7. Format the output as a JSON array. Each element should have:
            - "meal_type": one of "breakfast", "lunch", "dinner"
            - "recipe": an object with:
                - "title": string
                - "instructions": string
                - "ingredients": array of objects with:
                    - "name": string
                    - "quantity": number
                    - "unit": string

      Example of one entry in the array:
      {"meal_type":"breakfast","recipe":{"title":"Oat bowl","instructions":"Cook oats in water.","ingredients":[{"name":"oats","quantity":40,"unit":"g"},{"name":"water","quantity":200,"unit":"g"}]}}

      Respond with only the JSON array. Do not include markdown, code blocks, or extra text.
    PROMPT

    OpenaiService.new.generate_meal_plan(prompt, require_complete: true)
  end

  def parse_ai_response(response)
    # If already an array
    return response if response.is_a?(Array)

    # If string, try to parse JSON
    if response.is_a?(String)
      JSON.parse(response)
    else
      []
    end
  rescue JSON::ParserError
    Rails.logger.warn("AI response could not be parsed: #{response}")
    []
  end

  def create_meal_plan_in_db(meal_plan_data)
    prepared_ingredients = meal_plan_data.map do |meal|
      meal["recipe"]["ingredients"].map do |ing|
        service = NutritionService.new
        service.recipe_ingredient_attributes(ing["name"], ing["quantity"], ing["unit"])
      end
    end

    MealPlan.transaction do
      meal_plan = @user.meal_plans.create!(start_date: Date.today, end_date: Date.today)
      meal_plan_data.each_with_index do |meal, index|
        recipe_data = meal["recipe"]
        recipe = @user.recipes.create!(title: recipe_data["title"], instructions: recipe_data["instructions"])
        prepared_ingredients[index].each do |attributes|
          recipe.recipe_ingredients.find_or_create_by!(attributes.except(:nutrition_measure)) do |line|
            line.nutrition_measure = attributes[:nutrition_measure]
          end
        end
        MealPlanRecipe.create!(meal_plan: meal_plan, recipe: recipe, meal_type: meal["meal_type"].downcase)
      end
      meal_plan
    end
  end

  def validate_meal_plan!(meals)
    valid = meals.is_a?(Array) && meals.length == 3 && meals.all? do |meal|
      next false unless meal.is_a?(Hash) && meal["meal_type"].is_a?(String)

      recipe = meal["recipe"]
      recipe.is_a?(Hash) && recipe["title"].is_a?(String) && recipe["title"].present? &&
        recipe["instructions"].is_a?(String) && recipe["instructions"].present? &&
        recipe["ingredients"].is_a?(Array) && recipe["ingredients"].any? &&
        recipe["ingredients"].all? do |ingredient|
          ingredient.is_a?(Hash) && ingredient["name"].is_a?(String) && ingredient["name"].present? &&
            ingredient["quantity"].is_a?(Numeric) && ingredient["quantity"].finite? && ingredient["quantity"] > 0 &&
            ingredient["unit"].is_a?(String) && ingredient["unit"].present?
        end
    end
    valid &&= meals.map { |meal| meal["meal_type"].downcase }.sort == MealPlanRecipe.meal_types.keys.sort
    raise ArgumentError, "Meal plan must contain a complete breakfast, lunch and dinner" unless valid
  end
end
