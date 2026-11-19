require "test_helper"

class MealLogQuantityTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "meal-quantity@example.test", password: "password123",
      first_name: "Quantity", last_name: "Test", role: "member")
    @user.skip_confirmation!
    @user.save!
    @recipe = @user.recipes.create!(title: "Rice", instructions: "Cook")
    ingredient = Ingredient.create!(ingredient_name: "rice", serving_weight_grams: 25,
      calories_per_gram: 1, protein_per_gram: 0.1, carbs_per_gram: 0.2, fat_per_gram: 0.3)
    @recipe.recipe_ingredients.create!(ingredient: ingredient, quantity: 100, unit: "g")
  end

  { missing: {}, null: { quantity: nil }, blank: { quantity: "" },
    zero: { quantity: 0 }, negative: { quantity: -1 },
    nonnumeric: { quantity: "many" } }.each do |name, attributes|
    test "create rejects #{name} quantity without writing a meal log" do
      assert_no_difference "MealLog.count" do
        post meal_logs_path, params: { meal_log: { recipe_id: @recipe.id }.merge(attributes) },
          headers: auth_headers, as: :json
      end
      assert_quantity_error
    end
  end

  test "create accepts a positive fractional quantity" do
    assert_difference "MealLog.count", 1 do
      post meal_logs_path, params: { meal_log: { recipe_id: @recipe.id, quantity: 0.5 } },
        headers: auth_headers, as: :json
    end
    assert_response :created
    assert_in_delta 0.5, @user.meal_logs.reload.sole.quantity, 0.0001
  end

  { null: nil, blank: "", zero: 0, negative: -1, nonnumeric: "many" }.each do |name, quantity|
    test "update rejects #{name} quantity and retains persisted amount" do
      log = create_log
      patch "#{meal_logs_path}/#{log.id}", params: { meal_log: { quantity: quantity } },
        headers: auth_headers, as: :json
      assert_quantity_error
      assert_in_delta 2, log.reload.quantity, 0.0001
    end
  end

  test "partial update omitting quantity retains the existing valid amount" do
    log = create_log
    patch "#{meal_logs_path}/#{log.id}", params: { meal_log: { date: Date.yesterday.iso8601 } },
      headers: auth_headers, as: :json
    assert_response :success
    assert_in_delta 2, log.reload.quantity, 0.0001
    assert_equal Date.yesterday, log.date
  end

  %w[today today_totals].each do |endpoint|
    test "#{endpoint} rejects legacy missing quantity without modifying history" do
      log = create_log
      log.update_column(:quantity, nil)
      original = log.reload.attributes
      get "#{meal_logs_path}/#{endpoint}", headers: auth_headers
      assert_quantity_error
      assert_equal original, log.reload.attributes
    end
  end

  private

  def meal_logs_path
    "/api/v1/users/#{@user.id}/meal_logs"
  end

  def create_log
    @user.meal_logs.create!(recipe: @recipe, quantity: 2, date: Date.today)
  end

  def auth_headers
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def assert_quantity_error
    assert_response :unprocessable_entity
    assert_match(/quantity|servings/i, response.parsed_body.to_json)
    assert_match(/error/i, response.parsed_body.to_json)
  end
end
