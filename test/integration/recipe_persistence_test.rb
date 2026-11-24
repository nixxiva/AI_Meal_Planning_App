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
        patch "/api/v1/recipes/#{@recipe.id}", params: { recipe: { title: "Changed", instructions: "Changed instructions", recipe_ingredients: [ ingredient_data(30), ingredient_data(999) ] } }, headers: auth_headers, as: :json
        assert_response :unprocessable_entity
      end
    end
    assert_equal "Original", @recipe.reload.title
    assert_equal "Original instructions", @recipe.instructions
    assert_equal original, @recipe.recipe_ingredients.reload.order(:id).pluck(:id, :ingredient_id, :quantity, :unit)
  end

  test "valid replacement updates metadata and replaces ingredients" do
    with_providers do
      patch "/api/v1/recipes/#{@recipe.id}", params: { recipe: { title: "Changed", recipe_ingredients: [ ingredient_data(30) ] } }, headers: auth_headers, as: :json
      assert_response :success
    end
    assert_equal "Changed", @recipe.reload.title
    assert_equal [ [ "30", "g" ] ], @recipe.recipe_ingredients.reload.pluck(:quantity, :unit)
  end

  test "a later create write failure leaves no partial recipe" do
    assert_no_difference [ "Recipe.count", "RecipeIngredient.count" ] do
      with_providers do
        with_failing_ingredient_write do
          post "/api/v1/recipes", params: { recipe: { title: "New", recipe_ingredients: [ ingredient_data(30), ingredient_data(999) ] } }, headers: auth_headers, as: :json
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
    [ "not JSON", "[]", "{}", "null", incomplete.to_json, invalid_ingredient.to_json, duplicate_meals.to_json ].each do |output|
      assert_no_difference [ "MealPlan.count", "MealPlanRecipe.count", "Recipe.count", "RecipeIngredient.count" ] do
        with_providers(output) do
          post generation_path, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
          assert response.parsed_body["error"].present?
        end
      end
    end
  end

  test "AI breakfast lunch and dinner save with a prompt for one portion per recipe" do
    prompts = []
    with_providers(valid_plan.to_json, capture: ->(prompt) { prompts << prompt }) do
      assert_difference "MealPlan.count", 1 do
        post generation_path, headers: auth_headers, as: :json
        assert_response :success
      end
    end
    plan = @user.meal_plans.last
    assert_equal %w[breakfast dinner lunch], plan.meal_plan_recipes.map(&:meal_type).sort
    assert_equal 3, plan.recipes.count
    assert plan.recipes.all? { |recipe| recipe.recipe_ingredients.count == 1 }
    assert_includes prompts.sole, "Each recipe should make one suggested portion."
  end

  test "generation with a saved recipe title leaves the original recipe and diary alone" do
    @recipe.recipe_ingredients.destroy_all
    original_link = @recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 100, unit: "g")
    older_plan = @user.meal_plans.create!(start_date: Date.yesterday, end_date: Date.yesterday)
    old_entry = older_plan.meal_plan_recipes.create!(recipe: @recipe, meal_type: :breakfast)
    diary_path = "/api/v1/users/#{@user.id}/meal_logs"
    post diary_path, params: { meal_log: { recipe_id: @recipe.id, quantity: 1 } }, headers: auth_headers, as: :json
    assert_response :created
    diary_entry = @user.meal_logs.sole

    output = valid_plan
    output.first.fetch("recipe").merge!(
      "title" => @recipe.title,
      "instructions" => "New instructions",
      "ingredients" => [
        { "name" => "rice", "quantity" => 150, "unit" => "g" },
        { "name" => "rice", "quantity" => 150, "unit" => "g" },
        { "name" => "rice", "quantity" => 50, "unit" => "g" }
      ]
    )
    with_providers(output.to_json) do
      post generation_path, headers: auth_headers, as: :json
      assert_response :success
    end
    new_plan = @user.meal_plans.find(response.parsed_body.fetch("id"))
    breakfast = new_plan.meal_plan_recipes.find_by!(meal_type: :breakfast).recipe

    get "/api/v1/recipes/#{breakfast.id}", headers: auth_headers
    assert_response :success
    assert_equal 200, response.parsed_body.dig("data", "recipe", "total_calories")
    assert_not_equal @recipe.id, breakfast.id
    assert_equal "New instructions", breakfast.instructions
    assert_equal [ [ "150", "g" ], [ "50", "g" ] ], breakfast.recipe_ingredients.pluck(:quantity, :unit).sort

    assert_equal @recipe.id, old_entry.reload.recipe_id
    assert_equal @recipe.id, diary_entry.reload.recipe_id
    assert_equal "Original instructions", @recipe.reload.instructions
    assert_equal [ [ original_link.id, "100", "g" ] ], @recipe.recipe_ingredients.pluck(:id, :quantity, :unit)
    get "/api/v1/recipes/#{@recipe.id}", headers: auth_headers
    assert_response :success
    assert_equal 100, response.parsed_body.dig("data", "recipe", "total_calories")
    get "#{diary_path}/today_totals", headers: auth_headers
    assert_response :success
    assert_equal 100, response.parsed_body.fetch("calories")
    get "#{diary_path}/today", headers: auth_headers
    assert_response :success
    assert_equal 100, response.parsed_body.sole.dig("macros", "calories")
  end

  test "a later AI plan write failure rolls back the complete plan" do
    output = valid_plan
    output.last["recipe"]["ingredients"].first["quantity"] = 999
    assert_no_difference [ "MealPlan.count", "MealPlanRecipe.count", "Recipe.count", "RecipeIngredient.count" ] do
      with_providers(output.to_json) do
        with_failing_ingredient_write do
          post generation_path, headers: auth_headers, as: :json
          assert_response :unprocessable_entity
        end
      end
    end
  end

  {
    "empty ingredient list" => { ingredients: [] },
    "missing ingredient list" => { ingredients: nil },
    "blank title" => { title: "   " },
    "missing instructions" => { instructions: nil },
    "non-array ingredient list" => { ingredients: { name: "oats", quantity: 30, unit: "g" } },
    "malformed later row" => { ingredients: [ { name: "oats", quantity: 30, unit: "g" }, "more oats" ] },
    "invalid later name" => { ingredients: [ { name: "oats", quantity: 30, unit: "g" }, { name: "", quantity: 10, unit: "g" } ] },
    "invalid later quantity" => { ingredients: [ { name: "oats", quantity: 30, unit: "g" }, { name: "rice", quantity: -1, unit: "g" } ] },
    "invalid later unit" => { ingredients: [ { name: "oats", quantity: 30, unit: "g" }, { name: "rice", quantity: 10, unit: " " } ] }
  }.each do |scenario, invalid_fields|
    test "adjustment rejects #{scenario} before nutrition lookup or writes" do
      valid_ingredient = { name: "oats", quantity: 30, unit: "g" }
      payload = { title: "New", instructions: "Cook", ingredients: [ valid_ingredient ] }.merge(invalid_fields)
      nutrition = NutritionService.new
      lookups = []
      nutrients = { "foods" => [ { "serving_weight_grams" => 30, "nf_calories" => 30, "nf_protein" => 0,
        "nf_total_fat" => 0, "nf_total_carbohydrate" => 0 } ] }
      simulate_lookup = ->(name, *, **) do
        lookups << name
        nutrients
      end
      ai = Object.new
      ai.define_singleton_method(:generate_meal_plan) { |_| payload.to_json }

      OpenaiService.stub(:new, ai) do
        nutrition.stub(:fetch_nutrition_data, simulate_lookup) do
          NutritionService.stub(:new, nutrition) do
            assert_no_difference [ "Recipe.count", "RecipeIngredient.count", "Ingredient.count" ] do
              post "/api/v1/recipes/#{@recipe.id}/adjust", params: { target_protein: 0 }, headers: auth_headers, as: :json
            end
          end
        end
      end

      assert_response :unprocessable_entity
      assert_equal "AI returned an invalid recipe", response.parsed_body.fetch("message")
      assert_empty lookups
    end
  end

  test "a later adjustment write failure leaves no partial adjusted recipe" do
    output = { title: "New", instructions: "Cook", ingredients: [ { name: "rice", quantity: 30, unit: "g" }, { name: "rice", quantity: 999, unit: "g" } ] }
    assert_no_difference [ "Recipe.count", "RecipeIngredient.count" ] do
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
    output = { title: "New", instructions: "Cook", ingredients: [ { name: "rice", quantity: 30, unit: "g" } ] }.to_json
    with_providers(output, capture: ->(prompt) { captured_prompt = prompt }) do
      post "/api/v1/recipes/#{@recipe.id}/adjust", params: { target_calories: 30 }, headers: auth_headers, as: :json
      assert_response :success
    end
    assert_includes captured_prompt, "Health Goal: Maintain weight"
    assert_includes captured_prompt, "Keep portions reasonable for a single serving."
  end

  {
    "missed calorie goal" => [ { target_calories: 100 }, 30, "g", "missed" ],
    "exact match" => [ { target_calories: 100 }, 100, "g", "met" ],
    "inclusive decimal tolerance" => [ { target_calories: "0.50" }, 0.51, "g", "met" ],
    "just outside tolerance" => [ { target_calories: 100 }, 102.01, "g", "missed" ],
    "one of two targets missed" => [ { target_calories: 100, target_protein: 1 }, 100, "g", "missed" ],
    "genuine zero" => [ { target_protein: 0 }, 100, "g", "met" ],
    "unknown nutrition" => [ { target_calories: 100 }, 1, "cup", "unavailable" ]
  }.each do |scenario, (targets, quantity, unit, expected_status)|
    test "adjustment assesses #{scenario} using the saved recipe totals" do
      output = { title: "Adjusted rice", instructions: "Cook", ingredients: [ { name: "rice", quantity: quantity, unit: unit } ] }
      calls = 0
      with_providers(output.to_json, capture: ->(_) { calls += 1 }) do
        assert_difference "Recipe.count", 1 do
          post "/api/v1/recipes/#{@recipe.id}/adjust", params: targets, headers: auth_headers, as: :json
          assert_response :success
        end
      end
      assert_equal 1, calls
      assert_equal "success", response.parsed_body.fetch("status")
      data = response.parsed_body.fetch("data")
      assert_equal expected_status, data["target_status"]
      if unit == "g"
        assert_equal quantity, data.fetch("total_calories")
        assert_equal 0, data.fetch("total_protein")
        assert_equal true, data.fetch("nutrition_available")
      else
        assert_nil data.fetch("total_calories")
        assert_equal false, data.fetch("nutrition_available")
      end
      saved = @user.recipes.find(data.dig("adjusted_recipe", "id"))
      assert_equal [ [ quantity.to_s, unit ] ], saved.recipe_ingredients.pluck(:quantity, :unit)
    end
  end

  test "invalid adjustment targets are rejected before AI is called or a recipe is saved" do
    output = { title: "Unexpected adjustment", instructions: "Cook", ingredients: [ { name: "rice", quantity: 30, unit: "g" } ] }
    calls = 0
    with_providers(output.to_json, capture: ->(_) { calls += 1 }) do
      [ "bad", "", -1, "-1e-400", "Infinity", "NaN", "1e309", nil, true, [ 100 ], { value: 100 } ].each do |invalid|
        assert_no_difference [ "Recipe.count", "RecipeIngredient.count" ] do
          post "/api/v1/recipes/#{@recipe.id}/adjust", params: { target_calories: invalid }, headers: auth_headers, as: :json
          assert_response :unprocessable_entity, "Expected rejection for #{invalid.inspect}"
        end
      end
    end
    assert_equal 0, calls
  end

  test "adjustment without targets, create and update omit target assessment" do
    output = { title: "Adjusted rice", instructions: "Cook", ingredients: [ { name: "rice", quantity: 30, unit: "g" } ] }
    recipe_params = { recipe: { title: "Manual rice", recipe_ingredients: [ ingredient_data(30) ] } }
    with_providers(output.to_json) do
      post "/api/v1/recipes/#{@recipe.id}/adjust", headers: auth_headers, as: :json
      assert_response :success
      assert_not response.parsed_body.fetch("data").key?("target_status")
      post "/api/v1/recipes", params: recipe_params, headers: auth_headers, as: :json
      assert_response :success
      assert_not response.parsed_body.fetch("data").key?("target_status")
      patch "/api/v1/recipes/#{@recipe.id}", params: recipe_params, headers: auth_headers, as: :json
      assert_response :success
      assert_not response.parsed_body.fetch("data").key?("target_status")
    end
  end

  private

  def ingredient_data(quantity)
    { ingredient_name: "rice", quantity: quantity, unit: "g" }
  end

  def valid_plan
    %w[breakfast lunch dinner].map do |meal|
      { "meal_type" => meal, "recipe" => { "title" => meal, "instructions" => "Cook", "ingredients" => [ { "name" => "rice", "quantity" => 30, "unit" => "g" } ] } }
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
