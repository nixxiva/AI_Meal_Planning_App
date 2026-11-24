require "test_helper"
require "minitest/mock"

class NutritionAvailabilityTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  NUTRIENTS = %w[calories protein carbs fat].freeze
  STORED_NUTRIENTS = %w[calories_per_gram protein_per_gram carbs_per_gram fat_per_gram serving_weight_grams].freeze

  setup do
    @user = User.new(email: "availability@example.test", password: "password123",
      first_name: "Nutrition", last_name: "Test", role: "member")
    @user.skip_confirmation!
    @user.save!
    @ingredient = Ingredient.create!(ingredient_name: "availability rice", serving_weight_grams: 25,
      calories_per_gram: 1, protein_per_gram: 0.1, carbs_per_gram: 0.2, fat_per_gram: 0.3)
  end

  %w[cup piece unrecognized].each do |unit|
    test "#{unit} quantities expose unavailable nutrition across recipe and daily endpoints" do
      recipe = create_recipe(unit)
      details = recipe_details(recipe)
      assert_nutrition details.fetch("ingredients").sole, available: false, prefix: "total_"
      assert_nutrition details, available: false, prefix: "total_"
      assert_daily_nutrition recipe, available: false
    end
  end

  test "gram quantities expose measured nutrition across recipe and daily endpoints" do
    recipe = create_recipe("g")
    details = recipe_details(recipe)
    assert_nutrition details.fetch("ingredients").sole, available: true, prefix: "total_"
    assert_nutrition details, available: true, prefix: "total_"
    assert_equal 100.0, details.fetch("total_calories")
    assert_daily_nutrition recipe, available: true
    assert_equal 200.0, response.parsed_body.fetch("calories")
  end

  test "one unavailable ingredient makes the whole recipe and daily totals unavailable" do
    recipe = create_recipe("g")
    recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 1, unit: "cup")
    details = recipe_details(recipe)
    assert_nutrition details.fetch("ingredients").find { |item| item.fetch("unit") == "g" }, available: true, prefix: "total_"
    assert_nutrition details, available: false, prefix: "total_"
    assert_daily_nutrition recipe, available: false
  end

  test "positive serving weight with genuine zero nutrients stays available" do
    @ingredient.update!(calories_per_gram: 0, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 0)
    recipe = create_recipe("g")
    details = recipe_details(recipe)
    assert_nutrition details, available: true, prefix: "total_"
    assert_nutrition details.fetch("ingredients").sole, available: true, prefix: "total_"
    NUTRIENTS.each { |name| assert_equal 0, details.fetch("total_#{name}") }
    assert_daily_nutrition recipe, available: true
  end

  test "provider failure stores unknown values and a later valid response recovers" do
    service = NutritionService.new
    ingredient = service.stub(:fetch_nutrition_data, nil) do
      service.find_or_create_ingredient("provider unavailable", 1, "g")
    end
    STORED_NUTRIENTS.each { |name| assert_nil ingredient.reload.public_send(name), name }
    recovered = service.stub(:fetch_nutrition_data, provider_food(weight: 25, calories: 50)) do
      service.find_or_create_ingredient("provider unavailable", 1, "g")
    end
    assert_equal ingredient.id, recovered.id
    assert_equal 25, recovered.reload.serving_weight_grams
    assert_equal 2, recovered.calories_per_gram
  end

  test "cached genuine zero nutrients do not trigger another provider call" do
    @ingredient.update!(calories_per_gram: 0, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 0)
    service = NutritionService.new
    service.stub(:fetch_nutrition_data, ->(*) { flunk "Known zero nutrients must not be refetched" }) do
      result = service.find_or_create_ingredient(@ingredient.ingredient_name, 1, "g")
      assert_equal @ingredient.id, result.id
      assert_equal 25, result.serving_weight_grams
    end
  end

  test "provider zero serving weight stores unavailable nutrition without division errors" do
    service = NutritionService.new
    ingredient = service.stub(:fetch_nutrition_data, provider_food(weight: 0, calories: 50)) do
      service.find_or_create_ingredient("invalid provider weight", 1, "g")
    end
    STORED_NUTRIENTS.each { |name| assert_nil ingredient.reload.public_send(name), name }
  end

  test "recipes and diary use the precise per-gram protein from a single provider food" do
    food = { "serving_weight_grams" => 49, "nf_calories" => 33.81, "nf_protein" => 0.35,
      "nf_total_fat" => 0.08, "nf_total_carbohydrate" => 8.87,
      "full_nutrients" => [ { "attr_id" => 203, "value" => 0.3528 }, { "attr_id" => 204, "value" => 0.0784 },
        { "attr_id" => 205, "value" => 8.869 }, { "attr_id" => 208, "value" => 33.81 } ] }
    payload = { "foods" => [ food ] }
    reply = Struct.new(:code, :body, :parsed_response, :success?).new(200, payload.to_json, payload, true)
    queries = []
    lookup = ->(_url, body:, **) do
      queries << JSON.parse(body).fetch("query")
      reply
    end

    HTTParty.stub(:post, lookup) do
      [ 49, 500 ].each do |grams|
        post "/api/v1/recipes", params: { recipe: { title: "Grapes #{grams}", instructions: "Wash",
          recipe_ingredients: [ { ingredient_name: "Grape", quantity: grams, unit: "g" } ] } }, headers: auth_headers, as: :json
        assert_response :success
      end
    end

    assert_equal [ "49 g of grape" ], queries
    data = response.parsed_body.fetch("data")
    assert_equal 3.60, data.fetch("total_protein")
    ingredient = Ingredient.find_by!(ingredient_name: "grape")
    assert_in_delta 0.0072, ingredient.protein_per_gram, 0.000001
    assert_in_delta 0.0016, ingredient.fat_per_gram, 0.000001
    assert_in_delta 0.181, ingredient.carbs_per_gram, 0.000001
    assert_in_delta 0.69, ingredient.calories_per_gram, 0.000001

    recipe = @user.recipes.find(data.fetch("adjusted_recipe").fetch("id"))
    assert_equal 3.60, recipe_details(recipe).fetch("total_protein")
    assert_daily_nutrition recipe, available: true
    assert_equal 7.20, response.parsed_body.fetch("protein")
  end

  test "a valid detailed zero is saved and unusable details fall back to summary values" do
    payload = provider_food(weight: 25, calories: nil)
    payload.fetch("foods").sole["full_nutrients"] = [ nil,
      { "attr_id" => 208, "value" => 0 }, { "attr_id" => 203, "value" => -1 },
      { "attr_id" => 204, "value" => 2 }, { "attr_id" => 204, "value" => 3 } ]

    service = NutritionService.new
    ingredient = service.stub(:fetch_nutrition_data, payload) do
      service.find_or_create_ingredient("water", 25, "g")
    end

    assert_equal 25, ingredient.reload.serving_weight_grams
    assert_equal [ 0, 0, 0, 0 ], ingredient.attributes.values_at(*STORED_NUTRIENTS.first(4))
  end

  test "a provider response with multiple foods does not fill a single ingredient's nutrition" do
    service = NutritionService.new
    foods = provider_food(weight: 40, calories: 80).fetch("foods") +
      provider_food(weight: 60, calories: 60).fetch("foods")
    ingredient = service.stub(:fetch_nutrition_data, { "foods" => foods }) do
      service.find_or_create_ingredient("oats and milk", 100, "g")
    end

    STORED_NUTRIENTS.each { |name| assert_nil ingredient.reload.public_send(name), name }
    recipe = @user.recipes.create!(title: "Oats and milk", instructions: "Stir")
    recipe.recipe_ingredients.create!(ingredient: ingredient, quantity: 100, unit: "g")
    assert_nutrition recipe_details(recipe), available: false, prefix: "total_"
  end

  test "legacy provider fallback zeros are unavailable and recover on a later lookup" do
    @ingredient.update!(calories_per_gram: 0, protein_per_gram: 0, carbs_per_gram: 0, fat_per_gram: 0, serving_weight_grams: 0)
    recipe = create_recipe("g")
    assert_nutrition recipe_details(recipe), available: false, prefix: "total_"
    service = NutritionService.new
    service.stub(:fetch_nutrition_data, provider_food(weight: 25, calories: 50)) do
      service.find_or_create_ingredient(@ingredient.ingredient_name, 100, "g")
    end
    details = recipe_details(recipe)
    assert_nutrition details, available: true, prefix: "total_"
    assert_equal 200, details.fetch("total_calories")
  end

  test "supported mass conversions retain measured totals" do
    recipe = create_recipe("kg")
    recipe.recipe_ingredients.sole.update!(quantity: 0.1)
    details = recipe_details(recipe)
    assert_nutrition details, available: true, prefix: "total_"
    assert_equal 100, details.fetch("total_calories")
  end

  private

  def create_recipe(unit)
    recipe = @user.recipes.create!(title: "Nutrition availability", instructions: "Cook")
    recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 100, unit: unit)
    recipe
  end

  def auth_headers
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def recipe_details(recipe)
    get "/api/v1/recipes/#{recipe.id}", headers: auth_headers
    assert_response :success
    response.parsed_body.fetch("data").fetch("recipe")
  end

  def assert_daily_nutrition(recipe, available:)
    post "/api/v1/users/#{@user.id}/meal_logs", params: { meal_log: { recipe_id: recipe.id, quantity: 2 } },
      headers: auth_headers, as: :json
    assert_response :created
    get "/api/v1/users/#{@user.id}/meal_logs/today", headers: auth_headers
    assert_response :success
    assert_nutrition response.parsed_body.sole.fetch("macros"), available: available
    get "/api/v1/users/#{@user.id}/meal_logs/today_totals", headers: auth_headers
    assert_response :success
    assert_nutrition response.parsed_body, available: available
  end

  def assert_nutrition(data, available:, prefix: "")
    NUTRIENTS.each do |name|
      value = data.fetch("#{prefix}#{name}")
      available ? assert_kind_of(Numeric, value, name) : assert_nil(value, name)
    end
    assert_equal available, data.fetch("nutrition_available")
  end

  def provider_food(weight:, calories:)
    { "foods" => [ { "serving_weight_grams" => weight, "nf_calories" => calories,
      "nf_protein" => 0, "nf_total_fat" => 0, "nf_total_carbohydrate" => 0 } ] }
  end
end
