require "test_helper"
require "minitest/mock"

class RecipePersistenceTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "persistence@example.test", password: "password123", first_name: "Recipe", last_name: "Test", role: "member")
    @user.skip_confirmation!
    @user.save!
    @ingredient = Ingredient.create!(ingredient_name: "rice", calories_per_gram: 1, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 0, serving_weight_grams: 1)
    @recipe = @user.recipes.create!(title: "Original", instructions: "Original instructions")
    @recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 10, unit: "g")
    @recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 20, unit: "g")
  end

  test "a later replacement write failure preserves recipe metadata and original ingredient links" do
    original = @recipe.recipe_ingredients.order(:id).pluck(:id, :ingredient_id, :quantity, :unit)
    with_providers do
      with_failing_ingredient_write do
        patch "/api/v1/recipes/#{@recipe.id}", params: { recipe: { title: "Changed", instructions: "Changed instructions", recipe_ingredients: [ingredient_data(30), ingredient_data(999)] } }, headers: auth_headers, as: :json
        assert_response :unprocessable_entity
      end
    end
    assert_equal "Original", @recipe.reload.title
    assert_equal "Original instructions", @recipe.instructions
    assert_equal original, @recipe.recipe_ingredients.reload.order(:id).pluck(:id, :ingredient_id, :quantity, :unit)
  end

  test "valid replacement updates metadata and replaces ingredients" do
    with_providers do
      patch "/api/v1/recipes/#{@recipe.id}", params: { recipe: { title: "Changed", recipe_ingredients: [ingredient_data(30)] } }, headers: auth_headers, as: :json
      assert_response :success
    end
    assert_equal "Changed", @recipe.reload.title
    assert_equal [["30", "g"]], @recipe.recipe_ingredients.reload.pluck(:quantity, :unit)
  end

  test "a later create write failure leaves no partial recipe" do
    assert_no_difference ["Recipe.count", "RecipeIngredient.count"] do
      with_providers do
        with_failing_ingredient_write do
          post "/api/v1/recipes", params: { recipe: { title: "New", recipe_ingredients: [ingredient_data(30), ingredient_data(999)] } }, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
        end
      end
    end
  end

  test "invalid and incomplete AI plans fail without saving records" do
    incomplete = valid_plan
    incomplete.first["recipe"].delete("instructions")
    invalid_ingredient = valid_plan
    invalid_ingredient.first["recipe"]["ingredients"].first.delete("quantity")
    duplicate_meals = valid_plan
    duplicate_meals.last["meal_type"] = "breakfast"
    ["not JSON", "[]", "{}", "null", incomplete.to_json, invalid_ingredient.to_json, duplicate_meals.to_json].each do |output|
      assert_no_difference ["MealPlan.count", "MealPlanRecipe.count", "Recipe.count", "RecipeIngredient.count"] do
        with_providers(output) do
          post generation_path, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
          assert response.parsed_body["error"].present?
        end
      end
    end
  end

  test "valid AI breakfast lunch and dinner save correctly" do
    with_providers(valid_plan.to_json) do
      assert_difference "MealPlan.count", 1 do
        post generation_path, headers: auth_headers, as: :json
        assert_response :success
      end
    end
    plan = @user.meal_plans.last
    assert_equal %w[breakfast dinner lunch], plan.meal_plan_recipes.map(&:meal_type).sort
    assert_equal 3, plan.recipes.count
    assert plan.recipes.all? { |recipe| recipe.recipe_ingredients.count == 1 }
  end

  test "a later AI plan write failure rolls back the complete plan" do
    output = valid_plan
    output.last["recipe"]["ingredients"].first["quantity"] = 999
    assert_no_difference ["MealPlan.count", "MealPlanRecipe.count", "Recipe.count", "RecipeIngredient.count"] do
      with_providers(output.to_json) do
        with_failing_ingredient_write do
          post generation_path, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
        end
      end
    end
  end

  test "a later adjustment write failure leaves no partial adjusted recipe" do
    output = { title: "New", instructions: "Cook", ingredients: [{ name: "rice", quantity: 30, unit: "g" }, { name: "rice", quantity: 999, unit: "g" }] }
    assert_no_difference ["Recipe.count", "RecipeIngredient.count"] do
      with_providers(output.to_json) do
        with_failing_ingredient_write do
          post "/api/v1/recipes/#{@recipe.id}/adjust", params: { target_calories: 100 }, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
        end
      end
    end
    assert_equal "Original", @recipe.reload.title
  end

  test "adjustment sends the selected health goal to the provider" do
    @user.update!(health_goal: HealthGoal.create!(goal_name: "Maintain weight"))
    captured_prompt = nil
    output = { title: "New", instructions: "Cook", ingredients: [{ name: "rice", quantity: 30, unit: "g" }] }.to_json
    with_providers(output, capture: ->(prompt) { captured_prompt = prompt }) do
      post "/api/v1/recipes/#{@recipe.id}/adjust", params: { target_calories: 30 }, headers: auth_headers, as: :json
      assert_response :success
    end
    assert_includes captured_prompt, "Health Goal: Maintain weight"
  end

  private

  def ingredient_data(quantity)
    { ingredient_name: "rice", quantity: quantity, unit: "g" }
  end

  def valid_plan
    %w[breakfast lunch dinner].map do |meal|
      { "meal_type" => meal, "recipe" => { "title" => meal, "instructions" => "Cook", "ingredients" => [{ "name" => "rice", "quantity" => 30, "unit" => "g" }] } }
    end
  end

  def generation_path
    "/api/v1/users/#{@user.id}/meal_plans/generate"
  end

  def auth_headers
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i }, Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def with_providers(output = "[]", capture: nil)
    nutrition = NutritionService.allocate
    ai = Object.new
    ai.define_singleton_method(:generate_meal_plan) do |prompt|
      capture&.call(prompt)
      output
    end
    suggestion = Object.new
    suggestion.define_singleton_method(:suggest_substitute) { |_, **| nil }
    nutrition.stub(:find_or_create_ingredient, @ingredient) do
      NutritionService.stub(:new, nutrition) do
        OpenaiService.stub(:new, ai) do
          RecipeSuggestionService.stub(:new, suggestion) { yield }
        end
      end
    end
  end

  def with_failing_ingredient_write
    fail_write = proc do |record|
      if record.quantity == "999"
        record.errors.add(:base, "Injected later persistence failure")
        raise ActiveRecord::RecordInvalid, record
      end
    end
    RecipeIngredient.set_callback(:create, :before, fail_write)
    yield
  ensure
    RecipeIngredient.skip_callback(:create, :before, fail_write)
  end
end
