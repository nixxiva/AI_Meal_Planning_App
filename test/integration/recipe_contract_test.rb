require "test_helper"

class RecipeContractTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "contracts@example.test", password: "password123",
      first_name: "Contract", last_name: "Test", role: "member")
    @user.skip_confirmation!
    @user.save!
    @recipe = @user.recipes.create!(title: "Rice bowl", instructions: "Cook rice")
    ingredient = Ingredient.create!(ingredient_name: "rice")
    @recipe.recipe_ingredients.create!(ingredient: ingredient, quantity: 100, unit: "g")
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    @headers = { "Authorization" => "Bearer #{token}" }
  end

  test "ingredient filter returns matching owned recipes and leaves unfiltered listing working" do
    other = @user.recipes.create!(title: "Soup", instructions: "Boil")
    get "/api/v1/recipes", params: { ingredient: "rice" }, headers: @headers
    assert_response :success
    assert_equal [@recipe.id], response.parsed_body.dig("data", "recipes").map { |recipe| recipe["id"] }

    get "/api/v1/recipes", headers: @headers
    assert_response :success
    assert_equal [@recipe.id, other.id].sort, response.parsed_body.dig("data", "recipes").map { |recipe| recipe["id"] }.sort
  end

  test "rating returns its saved aggregate and rerating updates the existing rating" do
    post "/api/v1/recipes/#{@recipe.id}/rate", params: { rating: { rating: 4 } }, headers: @headers, as: :json
    assert_response :success
    assert_equal "success", response.parsed_body["status"]
    assert_equal 4.0, response.parsed_body.dig("data", "average_rating")
    assert_equal 1, response.parsed_body.dig("data", "total_ratings")
    assert_equal 4, @recipe.ratings.reload.sole.rating

    post "/api/v1/recipes/#{@recipe.id}/rate", params: { rating: { rating: 2 } }, headers: @headers, as: :json
    assert_response :success
    assert_equal 2.0, response.parsed_body.dig("data", "average_rating")
    assert_equal 1, @recipe.ratings.reload.count
    assert_equal 2, @recipe.ratings.sole.rating
  end
end
