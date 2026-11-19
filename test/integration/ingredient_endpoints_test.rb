require "test_helper"
require "minitest/mock"

class IngredientEndpointsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = create_user("ingredient-user")
    @admin = create_user("ingredient-admin", role: "admin")
    @ingredient = Ingredient.create!(ingredient_name: "brown rice", calories_per_gram: 1,
      protein_per_gram: 0.1, carbs_per_gram: 0.2, fat_per_gram: 0.03, serving_weight_grams: 100)
  end

  test "local search is public, literal, ordered and returns only public food fields" do
    Ingredient.create!(ingredient_name: "rice 100%", serving_weight_grams: 20)
    get "/api/v1/ingredients/search", params: { query: "RICE" }
    assert_response :success, response.body
    assert_equal ["brown rice", "rice 100%"], response.parsed_body.map { |row| row.fetch("ingredient_name") }
    assert_equal %w[id ingredient_name calories_per_gram protein_per_gram carbs_per_gram fat_per_gram serving_weight_grams].sort,
      response.parsed_body.first.keys.sort

    get "/api/v1/ingredients/search", params: { query: "%" }
    assert_response :success
    assert_equal ["rice 100%"], response.parsed_body.map { |row| row.fetch("ingredient_name") }
  end

  test "local search requires a query" do
    assert_equal "search", Rails.application.routes.recognize_path("/api/v1/ingredients/search", method: :get).fetch(:action)
    get "/api/v1/ingredients/search", as: :json
    assert_response :bad_request
  end

  test "signed in provider search calls Nutritionix without saving shared data" do
    service = Object.new
    calls = []
    service.define_singleton_method(:search_nutritionix) do |query, quantity:, unit:|
      calls << [query, quantity, unit]
      { "foods" => [{ "food_name" => "rice", "serving_weight_grams" => 100, "nf_calories" => 130,
        "nf_protein" => 2, "nf_total_fat" => 1, "nf_total_carbohydrate" => 28, "internal" => "hidden" }] }
    end
    NutritionixService.stub(:new, service) do
      post "/api/v1/ingredients/search_nutritionix", params: { query: "rice", quantity: 100, unit: "g" },
        headers: auth_headers(@user), as: :json
    end
    assert_response :success
    assert_equal [["rice", 100.0, "g"]], calls
    assert_equal "rice", response.parsed_body.dig("foods", 0, "food_name")
    refute response.body.include?("internal")
    assert_equal 1, Ingredient.count
  end

  test "provider lookup is not available without sign in and rejects invalid input before calling provider" do
    post "/api/v1/ingredients/search_nutritionix", params: { query: "rice" }, as: :json
    assert_response :unauthorized
    service = Object.new
    service.define_singleton_method(:search_nutritionix) { |*| flunk "Invalid input must not call provider" }
    NutritionixService.stub(:new, service) do
      post "/api/v1/ingredients/search_nutritionix", params: { query: "", quantity: -1 },
        headers: auth_headers(@user), as: :json
    end
    assert_response :unprocessable_entity
  end

  test "ingredient writes require admin permission and validate shared nutrient values" do
    assert_no_difference "Ingredient.count" do
      post "/api/v1/ingredients", params: { ingredient: { ingredient_name: "oats" } }, headers: auth_headers(@user), as: :json
      assert_response :unauthorized
    end
    post "/api/v1/ingredients", params: { ingredient: { ingredient_name: "oats" } }, headers: auth_headers(@admin), as: :json
    assert_response :created
    id = response.parsed_body.fetch("id")
    assert_equal "oats", Ingredient.find(id).ingredient_name

    patch "/api/v1/ingredients/#{id}", params: { ingredient: { calories_per_gram: -1 } }, headers: auth_headers(@admin), as: :json
    assert_response :unprocessable_entity
    assert_nil Ingredient.find(id).calories_per_gram
  end

  test "ingredient deletion is admin only and protects recipe and pantry references" do
    recipe = @user.recipes.create!(title: "Rice", instructions: "Cook")
    recipe.recipe_ingredients.create!(ingredient: @ingredient, quantity: 100, unit: "g")
    delete "/api/v1/ingredients/#{@ingredient.id}", headers: auth_headers(@admin), as: :json
    assert_response :conflict
    assert Ingredient.exists?(@ingredient.id)

    removable = Ingredient.create!(ingredient_name: "spare")
    delete "/api/v1/ingredients/#{removable.id}", headers: auth_headers(@user), as: :json
    assert_response :unauthorized
    delete "/api/v1/ingredients/#{removable.id}", headers: auth_headers(@admin), as: :json
    assert_response :no_content
    refute Ingredient.exists?(removable.id)
  end

  private

  def create_user(name, role: "member")
    user = User.new(email: "#{name}@example.test", password: "password123", first_name: name, last_name: "Test", role: role)
    user.skip_confirmation!
    user.save!
    user
  end

  def auth_headers(user)
    token = JWT.encode({ sub: user.id.to_s, jti: user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
