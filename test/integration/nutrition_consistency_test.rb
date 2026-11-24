require "test_helper"

class NutritionConsistencyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @ingredient = Ingredient.create!(ingredient_name: "rice", serving_weight_grams: 25,
      calories_per_gram: 1, protein_per_gram: 0.1, carbs_per_gram: 0.2, fat_per_gram: 0.3)
    @large_user, @large_recipe = create_recipe("large", 100)
    @small_user, @small_recipe = create_recipe("small", 50)
  end

  test "recipe details scale the same shared ingredient by each recipe amount" do
    large = recipe_details(@large_user, @large_recipe)
    small = recipe_details(@small_user, @small_recipe)
    %w[calories protein carbs fat].each do |nutrient|
      assert_in_delta small.fetch("total_#{nutrient}") * 2, large.fetch("total_#{nutrient}"), 0.001
    end
    assert_equal 100.0, large.fetch("total_calories")
    assert_equal 50.0, small.fetch("total_calories")
    assert_equal 100.0, large.fetch("ingredients").sole.fetch("total_calories")
  end

  test "daily totals use recipe amounts and eaten servings independently for each user" do
    record_meal(@large_user, @large_recipe, 2)
    record_meal(@small_user, @small_recipe, 3)
    assert_daily_totals(@large_user, calories: 200, protein: 20, carbs: 40, fat: 60)
    assert_daily_totals(@small_user, calories: 150, protein: 15, carbs: 30, fat: 45)

    @ingredient.update!(serving_weight_grams: 500)
    assert_daily_totals(@large_user, calories: 200, protein: 20, carbs: 40, fat: 60)
    assert_daily_totals(@small_user, calories: 150, protein: 15, carbs: 30, fat: 45)
  end

  test "today list agrees with recipe totals multiplied by eaten servings" do
    record_meal(@large_user, @large_recipe, 2)
    details = recipe_details(@large_user, @large_recipe)
    get "/api/v1/users/#{@large_user.id}/meal_logs/today", headers: auth_headers(@large_user)
    assert_response :success
    meal = response.parsed_body.sole
    assert_equal 2, meal.fetch("quantity")
    %w[calories protein carbs fat].each do |nutrient|
      assert_in_delta details.fetch("total_#{nutrient}") * 2, meal.fetch("macros").fetch(nutrient), 0.001
    end
  end

  test "daily totals round after adding fractional portions" do
    3.times { @large_user.meal_logs.create!(recipe: @large_recipe, quantity: 0.00334, date: Date.today) }

    get "/api/v1/users/#{@large_user.id}/meal_logs/today", headers: auth_headers(@large_user)
    assert_response :success
    assert_equal [ 0.33, 0.33, 0.33 ], response.parsed_body.map { |meal| meal.fetch("macros").fetch("calories") }

    assert_daily_totals(@large_user, calories: 1.0, protein: 0.10, carbs: 0.20, fat: 0.30)
  end

  private

  def create_recipe(name, grams)
    user = User.new(email: "nutrition-#{name}@example.test", password: "password123",
      first_name: name, last_name: "Test", role: "member")
    user.skip_confirmation!
    user.save!
    recipe = user.recipes.create!(title: "#{name} rice", instructions: "Cook")
    recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: grams, unit: "g")
    [ user, recipe ]
  end

  def auth_headers(user)
    token = JWT.encode({ sub: user.id.to_s, jti: user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def recipe_details(user, recipe)
    get "/api/v1/recipes/#{recipe.id}", headers: auth_headers(user)
    assert_response :success
    response.parsed_body.fetch("data").fetch("recipe")
  end

  def record_meal(user, recipe, servings)
    post "/api/v1/users/#{user.id}/meal_logs", params: { meal_log: { recipe_id: recipe.id, quantity: servings } },
      headers: auth_headers(user), as: :json
    assert_response :created
    assert_equal servings, user.meal_logs.reload.sole.quantity
  end

  def assert_daily_totals(user, expected)
    get "/api/v1/users/#{user.id}/meal_logs/today_totals", headers: auth_headers(user)
    assert_response :success
    expected.each { |nutrient, value| assert_in_delta value, response.parsed_body.fetch(nutrient.to_s), 0.001 }
  end
end
