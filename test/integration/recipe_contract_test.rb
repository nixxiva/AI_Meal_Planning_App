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
    @recipe.recipe_ingredients.create!(ingredient: @recipe.ingredients.sole, quantity: 50, unit: "g")
    other = @user.recipes.create!(title: "Soup", instructions: "Boil")
    get "/api/v1/recipes", params: { ingredient: "rice" }, headers: @headers
    assert_response :success
    assert_equal [ @recipe.id ], response.parsed_body.dig("data", "recipes").map { |recipe| recipe["id"] }
    assert_equal 1, response.parsed_body.dig("data", "total")

    get "/api/v1/recipes", headers: @headers
    assert_response :success
    assert_equal [ @recipe.id, other.id ].sort, response.parsed_body.dig("data", "recipes").map { |recipe| recipe["id"] }.sort
  end

  test "recipe listing fetches rating summaries together and preserves unrated recipes" do
    @recipe.ratings.create!(user: @user, rating: 4)
    @recipe.ratings.create!(user: @user, rating: nil)
    other_recipes = 11.times.map { |number| @user.recipes.create!(title: "Soup #{number}", instructions: "Boil") }

    assert_queries_match(/\bFROM "(?:recipes|ratings|recipe_ingredients|ingredients)"/, count: 2) do
      get "/api/v1/recipes", headers: @headers
      assert_response :success
    end

    data = response.parsed_body.fetch("data")
    assert_equal 12, data.fetch("total")
    summaries = data.fetch("recipes").index_by { |recipe| recipe.fetch("id") }
    assert_equal [ @recipe.id, *other_recipes.map(&:id) ].sort, summaries.keys.sort
    assert_equal [ 4.0, 2 ], summaries.fetch(@recipe.id).values_at("average_rating", "total_ratings")
    assert_equal [ 0.0, 0 ], summaries.fetch(other_recipes.first.id).values_at("average_rating", "total_ratings")
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
