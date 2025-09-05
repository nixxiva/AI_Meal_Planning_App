class MealPlanGeneratorService
  def initialize(user)
    @user = user
  end

  # generate 1 day plan only
  def generate_1_day_plan
    preferences = gather_preferences
    ai_response = call_ai_service(preferences)
    meal_plan_data = parse_ai_response(ai_response)

    create_meal_plan_in_db(meal_plan_data)
  end

  private

  def gather_preferences
    {
      dietary_preferences: @user.dietary_preferences.pluck(:pref_name),
      allergies: @user.allergies.pluck(:allergy_name),
      disliked_ingredients: @user.disliked_ingredients.pluck(:ingredient_name),
      health_goal: @user.health_goal&.goal_name
    }
  end

  def call_ai_service(preferences)
    prompt = <<~PROMPT
      You are a helpful nutritionist.

      Create a 1-day meal plan for a user with:
      Dietary preferences: #{preferences[:dietary_preferences].join(", ")}
      Allergies: #{preferences[:allergies].join(", ")}
      Disliked ingredients: #{preferences[:disliked_ingredients].join(", ")}
      Health goal: #{preferences[:health_goal]}

      Requirements:
      1. Provide exactly 3 meals: breakfast, lunch, and dinner.
      2. Each meal must include the key "meal_type" with value "breakfast", "lunch", or "dinner".
      3. Format the output strictly as a JSON array. Each element must be:
          {
            "meal_type": "breakfast|lunch|dinner"
            "recipe": {
              "title": string,
              "instructions": string,
              "ingredients": [
                {
                  "name": string,
                  "quantity": number,
                  "unit": string
                }
              ]
            }
          }

      Respond only with valid JSON, no markdown, no extra text.
    PROMPT

    OpenaiService.new.generate_meal_plan(prompt)
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
    meal_plan = @user.meal_plans.create!(start_date: Date.today, end_date: Date.today)

    meal_plan_data.each do |meal|
      recipe_data = meal["recipe"]
      next unless recipe_data["title"].present? && recipe_data["instructions"].present?

      recipe = @user.recipes.find_or_create_by!(title: recipe_data["title"]) do |r|
        r.instructions = recipe_data["instructions"]
      end

      recipe_data["ingredients"]&.each do |ing|
        next unless ing["name"].present?

        nutrition = NutritionixService.new.search_food(ing["name"]) || {}

        ingredient = Ingredient.find_or_create_by!(ingredient_name: ing["name"]) do |i|
          i.serving_weight_grams = nutrition["serving_weight_grams"] || 0
          i.calories_per_gram     = nutrition["calories_per_gram"] || 0
          i.protein_per_gram      = nutrition["protein_per_gram"] || 0
          i.carbs_per_gram        = nutrition["carbs_per_gram"] || 0
          i.fat_per_gram          = nutrition["fat_per_gram"] || 0
        end

        RecipeIngredient.find_or_create_by!(
          recipe: recipe,
          ingredient: ingredient,
          quantity: ing["quantity"] || 0,
          unit: ing["unit"] || ""
        )
      end

      meal_type_index = meal["meal_type"].to_i

      if MealPlanRecipe.meal_types.values.include?(meal_type_index)
        MealPlanRecipe.create!(
          meal_plan: meal_plan,
          recipe: recipe,
          meal_type: meal_type_index
        )
      else
        # Rails.logger.warn "Skipping invalid meal_type: #{meal["meal_type"]}"
        Rails.logger.info "AI meal_type raw value: #{meal['meal_type'].inspect}"
      end
    end

    meal_plan 
    
  end
end
