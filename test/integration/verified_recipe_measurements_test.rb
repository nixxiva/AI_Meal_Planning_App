require "test_helper"
require "minitest/mock"

class VerifiedRecipeMeasurementsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  RICE = "regular unenriched long-grain white rice cooked without salt"
  EGG = "large whole raw egg"
  TUNA = "starkist 5 oz chunk light tuna in water drained"

  setup do
    @user = User.new(email: "verified-measurements@example.test", password: "password123",
      first_name: "Verified", last_name: "Measurements", role: "member")
    @user.skip_confirmation!
    @user.save!
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    @headers = { "Authorization" => "Bearer #{token}" }
  end

  {
    "half cup of cooked rice" => [ RICE, 0.5, "cup", 79, [ 102.7, 2.13, 22.25, 0.22 ] ],
    "two large raw eggs" => [ EGG, 2, "eggs", 100, [ 143.0, 12.56, 0.72, 9.51 ] ],
    "half a drained labeled can" => [ TUNA, 0.5, "can", 56.5, [ 45.0, 10, 0, 0.25 ] ]
  }.each do |label, (name, quantity, unit, grams, expected_macros)|
    test "#{label} matches explicit grams in recipe and diary totals" do
      ingredient = seed_incorrect_profile(name)
      before = ingredient.attributes
      measured = create_recipe(name, quantity, unit)
      weighed = create_recipe(name, grams, "g")

      assert_equal expected_macros, measured.values_at(*macro_keys)
      assert_equal weighed.values_at(*macro_keys), measured.values_at(*macro_keys)
      assert_equal before, ingredient.reload.attributes
      assert_equal [ quantity.to_s, unit ], measured.fetch("ingredients").sole.values_at("quantity", "unit")
      saved_line = @user.recipes.find(measured.fetch("id")).recipe_ingredients.sole
      assert_equal grams, saved_line.nutrition_measure.fetch("grams")

      post diary_path, params: { meal_log: { recipe_id: measured.fetch("id"), quantity: 2 } },
        headers: @headers, as: :json
      assert_response :created
      get "#{diary_path}/today_totals", headers: @headers
      assert_response :success
      assert_equal true, response.parsed_body.fetch("nutrition_available")
      assert_equal (expected_macros.first * 2).round(2), response.parsed_body.fetch("calories")
    end
  end

  test "older and ambiguous ingredients remain unavailable with warm cached values" do
    ingredient = seed_incorrect_profile(RICE)
    legacy = @user.recipes.create!(title: "Older recipe", instructions: "Cook")
    legacy.recipe_ingredients.create!(ingredient: ingredient, quantity: 1, unit: "cup")
    post diary_path, params: { meal_log: { recipe_id: legacy.id, quantity: 1 } }, headers: @headers, as: :json
    assert_response :created

    create_recipe(RICE, 0.5, "cup")
    get "#{diary_path}/today_totals", headers: @headers
    assert_response :success
    assert_equal false, response.parsed_body.fetch("nutrition_available")
    patch "/api/v1/recipes/#{legacy.id}", params: recipe_payload(RICE, 1.0, "cup"), headers: @headers, as: :json
    assert_response :success
    assert_equal false, response.parsed_body.dig("data", "nutrition_available")
    patch "/api/v1/recipes/#{legacy.id}", params: recipe_payload(RICE, 0.5, "cup"), headers: @headers, as: :json
    assert_response :success
    assert_equal 102.7, response.parsed_body.dig("data", "total_calories")

    [ [ "raw long-grain white rice", "cup" ], [ "whole raw egg", "egg" ],
      [ "starkist 5 oz chunk light tuna in water", "can" ], [ RICE, "fluid ounces" ] ].each do |name, unit|
      seed_incorrect_profile(name) unless name == RICE
      data = create_recipe(name, 1, unit)
      assert_equal false, data.fetch("nutrition_available")
      assert_nil data.fetch("total_calories")
    end
  end

  test "AI plans and adjustments use the same reference without exposing the snapshot" do
    ingredient_row = { name: EGG, quantity: 2, unit: "eggs" }
    meals = %w[breakfast lunch dinner].map do |type|
      { meal_type: type, recipe: { title: type, instructions: "Cook",
        ingredients: [ ingredient_row, ingredient_row, ingredient_row.merge(quantity: 1) ] } }
    end
    generated = nil
    with_reply(meals, substitute: true) do
      post "#{plans_path}/generate", headers: @headers, as: :json
      assert_response :success
      generated = response.parsed_body
    end
    plan = @user.meal_plans.find(generated.fetch("id"))
    recipe = plan.meal_plan_recipes.find_by!(meal_type: :breakfast).recipe
    assert_equal %w[1 2], recipe.recipe_ingredients.pluck(:quantity).sort
    assert_equal 214.5, recipe_details(recipe).fetch("total_calories")
    assert_no_snapshot(generated.fetch("meal_plan_recipes"))

    get plans_path, headers: @headers
    assert_response :success
    assert_no_snapshot(response.parsed_body.sole.fetch("meal_plan_recipes"))

    get "#{plans_path}/#{plan.id}", headers: @headers
    assert_response :success
    assert_no_snapshot(response.parsed_body.fetch("data").fetch("meal_plan_recipes"))

    with_reply({ title: "Adjusted", instructions: "Cook", ingredients: [ ingredient_row ] }) do
      post "/api/v1/recipes/#{recipe.id}/adjust", params: { target_calories: 143 }, headers: @headers, as: :json
      assert_response :success
      assert_equal 143.0, response.parsed_body.dig("data", "total_calories")
      assert_equal "met", response.parsed_body.dig("data", "target_status")
    end
  end

  private

  def seed_incorrect_profile(name)
    Ingredient.create!(ingredient_name: name, serving_weight_grams: 1,
      calories_per_gram: 9, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 1)
  end

  def create_recipe(name, quantity, unit)
    post "/api/v1/recipes", params: recipe_payload(name, quantity, unit), headers: @headers, as: :json
    assert_response :success
    response.parsed_body.fetch("data").fetch("adjusted_recipe")
  end

  def recipe_payload(name, quantity, unit)
    { recipe: { title: "New recipe", instructions: "Cook",
      recipe_ingredients: [ { ingredient_name: name, quantity: quantity, unit: unit } ] } }
  end

  def recipe_details(recipe)
    get "/api/v1/recipes/#{recipe.id}", headers: @headers
    assert_response :success
    response.parsed_body.dig("data", "recipe")
  end

  def macro_keys
    %w[total_calories total_protein total_carbs total_fat]
  end

  def diary_path
    "/api/v1/users/#{@user.id}/meal_logs"
  end

  def plans_path
    "/api/v1/users/#{@user.id}/meal_plans"
  end

  def with_reply(payload, substitute: false)
    ai = Object.new
    ai.define_singleton_method(:generate_meal_plan) do |prompt|
      substitute && prompt.include?("Suggest one practical substitute") ? "" : payload.to_json
    end
    HTTParty.stub(:post, ->(*) { flunk "Known reference lines should not call Nutritionix" }) do
      OpenaiService.stub(:new, ai) { yield }
    end
  end

  def assert_no_snapshot(meals)
    meals.each do |meal|
      meal.fetch("recipe").fetch("recipe_ingredients").each do |line|
        refute line.key?("nutrition_measure")
      end
    end
  end
end
