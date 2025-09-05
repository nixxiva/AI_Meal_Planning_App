class RecipeAdjustmentService
  def initialize(recipe, user)
		@recipe = recipe
		@user = user
    @nutrition_service = NutritionService.new
	end

	def adjust_recipe(target_nutrition)
		preferences = gather_user_context
    current_nutrition = @nutrition_service.update_recipe_nutrition(@recipe)

		ai_response = call_ai_for_adjustment(target_nutrition, preferences, current_nutrition)
		adjusted_recipe_data = parse_ai_response(ai_response)

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

	def call_ai_for_adjustment(target_nutrition, preferences, current_nutrition)
    current_ingredients = @recipe.recipe_ingredients.map do |ri|
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
      - Health Goal: #{preferences[:health_goals]}
      
      Adjust by:
      1. Substituting similar ingredients
      2. Making small quantity adjustments (avoid huge portions)
      3. Adding complementary ingredients if needed
      
      Keep portions reasonable for a single serving.
      
      Provide adjusted recipe as JSON:
      {
        "title": "string",
        "instructions": "string", 
        "ingredients": [
          {"name": "string", "quantity": number, "unit": "string"}
        ]
      }
      
      Respond with only valid JSON.
    PROMPT

      OpenaiService.new.generate_meal_plan(prompt)
    end

  def parse_ai_response(response)
    return response if response.is_a?(Hash)
    
    if response.is_a?(String)
      JSON.parse(response)
    else
      {}
    end
  rescue JSON::ParserError
    Rails.logger.warn("AI response could not be parsed: #{response}")
    {}
  end

  def process_adjusted_recipe(original_recipe)
    if original_recipe.is_a?(Hash) && original_recipe["title"]
      adjusted_recipe_data = {
    "title" => "Adjusted #{original_recipe["title"]}",
    "instructions" => original_recipe["instructions"],
    "ingredients" => original_recipe["ingredients"]
    }

      new_recipe = Recipe.create!(
        title: adjusted_recipe_data["title"],
        instructions: adjusted_recipe_data["instructions"],
        user: @user
      )

      adjusted_recipe_data["ingredients"].each do |ingredient_data|
        ingredient = @nutrition_service.find_or_create_ingredient(ingredient_data["name"], ingredient_data["quantity"], ingredient_data["unit"])

        # Create the link between the new recipe and the ingredient
        RecipeIngredient.create!(
          recipe: new_recipe,
          ingredient: ingredient,
          quantity: ingredient_data["quantity"],
          unit: ingredient_data["unit"]
        )
      end

      nutrition_summary = @nutrition_service.update_recipe_nutrition(new_recipe)
      new_recipe
    else
      Rails.logger.error "Invalid AI response format"
      return nil
    end
  end
end
