class RecipeAdjustmentService
  class InvalidRecipe < StandardError; end

  def initialize(recipe, user)
    @recipe = recipe
    @user = user
    @nutrition_service = NutritionService.new
  end

  def adjust_recipe(target_nutrition)
    preferences = gather_user_context

    ai_response = call_ai_for_adjustment(target_nutrition, preferences)
    adjusted_recipe_data = parse_ai_response(ai_response)
    validate_recipe!(adjusted_recipe_data)

    process_adjusted_recipe(adjusted_recipe_data)
  end

  private

  def gather_user_context
    {
      dietary_preferences: @user.dietary_preferences.pluck(:pref_name),
      allergies: @user.allergies.pluck(:allergy_name),
      disliked_ingredients: @user.disliked_ingredients.pluck(:ingredient_name),
      health_goal: @user.health_goal&.goal_name
    }
  end

  def call_ai_for_adjustment(target_nutrition, preferences)
    current_ingredients = @recipe.recipe_ingredients.includes(:ingredient).map do |ri|
      {
        name: ri.ingredient.ingredient_name,
        quantity: ri.quantity,
        unit: ri.unit
      }
    end

    prompt = <<~PROMPT
      You are a helpful nutritionist. Adjust this recipe to meet the target nutrition goals within 2% or as CLOSE as possible.

      Current Recipe: "#{@recipe.title}"
      Current Ingredients: #{current_ingredients.to_json}

      Target Nutrition:
      - Calories: #{target_nutrition[:target_calories]}
      - Protein: #{target_nutrition[:target_protein]}g
      - Carbs: #{target_nutrition[:target_carbs]}g
      - Fat: #{target_nutrition[:target_fat]}g

      User Constraints:
      - Dietary preferences: #{preferences[:dietary_preferences].join(", ")}
      - Allergies: #{preferences[:allergies].join(", ")}
      - Disliked ingredients: #{preferences[:disliked_ingredients].join(", ")}
      - Health Goal: #{preferences[:health_goal]}

      Adjust by:
      1. Substituting similar ingredients
      2. Making small quantity adjustments (avoid huge portions)
      3. Adding complementary ingredients if needed

      Keep portions reasonable for a single serving.

      Provide adjusted recipe as JSON:
      {
        "title": "string",
        "instructions": "string",#{' '}
        "ingredients": [
          {"name": "string", "quantity": number, "unit": "string"}
        ]
      }

      Respond with only valid JSON.
    PROMPT

      OpenaiService.new.generate_meal_plan(prompt)
    end

  def parse_ai_response(response)
    response.is_a?(String) ? JSON.parse(response) : response
  rescue JSON::ParserError
    raise InvalidRecipe
  end

  def validate_recipe!(recipe)
    raise InvalidRecipe unless recipe.is_a?(Hash)

    ingredients = recipe["ingredients"]
    valid = recipe["title"].is_a?(String) && recipe["title"].present? &&
      recipe["instructions"].is_a?(String) && recipe["instructions"].present? &&
      ingredients.is_a?(Array) && ingredients.any? && ingredients.all? do |ingredient|
        next false unless ingredient.is_a?(Hash)

        quantity = ingredient["quantity"]
        ingredient["name"].is_a?(String) && ingredient["name"].present? &&
          ingredient["unit"].is_a?(String) && ingredient["unit"].present? &&
          quantity.is_a?(Numeric) && quantity.real? && quantity.finite? && quantity.positive?
      end

    raise InvalidRecipe unless valid
  end

  def process_adjusted_recipe(adjusted_recipe_data)
    ingredients = adjusted_recipe_data["ingredients"].map do |ingredient_data|
      @nutrition_service.recipe_ingredient_attributes(ingredient_data["name"], ingredient_data["quantity"], ingredient_data["unit"])
    end

    Recipe.transaction do
      new_recipe = Recipe.create!(
        title: "Adjusted #{adjusted_recipe_data["title"]}",
        instructions: adjusted_recipe_data["instructions"],
        user: @user
      )

      ingredients.each do |attributes|
        new_recipe.recipe_ingredients.create!(attributes)
      end
      new_recipe
    end
  end
end
