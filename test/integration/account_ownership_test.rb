require "test_helper"
require "minitest/mock"

class AccountOwnershipTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @owner = create_user("owner")
    @other = create_user("other")
    @plan = @other.meal_plans.create!(start_date: Date.current, end_date: Date.current)
    @recipe = @other.recipes.create!(title: "Other recipe", instructions: "Cook")
    @link = @plan.meal_plan_recipes.create!(recipe: @recipe, meal_type: :lunch)
  end

  test "every affected action rejects another user before services or writes" do
    base = "/api/v1/users/#{@other.id}"
    requests = [
      [ :get, "#{base}/pantry_items", {} ],
      [ :post, "#{base}/pantry_items", { pantry_item: { name: "rice", quantity: 1, unit: "g" } } ],
      [ :patch, "#{base}/pantry_items/1", { pantry_item: { quantity: 2 } } ],
      [ :delete, "#{base}/pantry_items/1", {} ],
      [ :get, "#{base}/meal_plans", {} ],
      [ :post, "#{base}/meal_plans", { meal_plan: { start_date: Date.current, end_date: Date.current } } ],
      [ :get, "#{base}/meal_plans/#{@plan.id}", {} ],
      [ :delete, "#{base}/meal_plans/#{@plan.id}", {} ],
      [ :post, "#{base}/meal_plans/generate", {} ],
      [ :post, "#{base}/meal_plans/#{@plan.id}/meal_plan_recipes", { meal_plan_recipe: { recipe_id: @recipe.id } } ],
      [ :delete, "#{base}/meal_plans/#{@plan.id}/meal_plan_recipes/#{@link.id}", {} ]
    ]

    forbidden_service = ->(*) { flunk "Rejected requests must not initialize external services" }
    NutritionService.stub(:new, forbidden_service) do
      MealPlanGeneratorService.stub(:new, forbidden_service) do
        assert_no_difference [ "MealPlan.count", "MealPlanRecipe.count", "PantryItem.count", "Recipe.count", "Ingredient.count" ] do
          requests.each do |method, path, params|
            public_send(method, path, params: params.presence, headers: auth_headers(@owner), as: :json)
            assert_response :forbidden, "#{method.upcase} #{path}"
          end
        end
      end
    end
    assert MealPlan.exists?(@plan.id)
    assert MealPlanRecipe.exists?(@link.id)
  end

  test "a nonexistent URL user is rejected without silently using the caller" do
    get "/api/v1/users/0/meal_plans", headers: auth_headers(@owner), as: :json
    assert_response :forbidden
  end

  test "administrators receive no ownership bypass" do
    @owner.update!(role: "admin")
    get "/api/v1/users/#{@other.id}/pantry_items", headers: auth_headers(@owner), as: :json
    assert_response :forbidden
  end

  test "authentication is still required" do
    get "/api/v1/users/#{@owner.id}/meal_plans", as: :json
    assert_response :unauthorized
  end

  test "owners can list their pantry and create and read their meal plans" do
    get "/api/v1/users/#{@owner.id}/pantry_items", headers: auth_headers(@owner), as: :json
    assert_response :success

    assert_difference "@owner.meal_plans.count", 1 do
      post "/api/v1/users/#{@owner.id}/meal_plans",
        params: { meal_plan: { start_date: Date.current, end_date: Date.current } },
        headers: auth_headers(@owner), as: :json
      assert_response :success
    end

    get "/api/v1/users/#{@owner.id}/meal_plans", headers: auth_headers(@owner), as: :json
    assert_response :success
    assert_equal @owner.meal_plans.pluck(:id), response.parsed_body.map { |plan| plan.fetch("id") }
  end

  test "an owned URL cannot expose another user's child records" do
    base = "/api/v1/users/#{@owner.id}/meal_plans/#{@plan.id}"
    get base, headers: auth_headers(@owner), as: :json
    assert_response :not_found

    assert_no_difference "MealPlanRecipe.count" do
      delete "#{base}/meal_plan_recipes/#{@link.id}", headers: auth_headers(@owner), as: :json
      assert_response :not_found
    end
  end

  test "owners can add and remove recipes from their own plans" do
    plan = @owner.meal_plans.create!(start_date: Date.current, end_date: Date.current)
    recipe = @owner.recipes.create!(title: "Own recipe", instructions: "Cook")
    path = "/api/v1/users/#{@owner.id}/meal_plans/#{plan.id}/meal_plan_recipes"

    assert_difference "plan.meal_plan_recipes.count", 1 do
      post path, params: { meal_plan_recipe: { recipe_id: recipe.id } }, headers: auth_headers(@owner), as: :json
      assert_response :created
    end

    assert_difference "plan.meal_plan_recipes.count", -1 do
      delete "#{path}/#{plan.meal_plan_recipes.first.id}", headers: auth_headers(@owner), as: :json
      assert_response :success
    end
  end

  test "admin account management routes are unavailable" do
    [ [ :get, "" ], [ :post, "" ], [ :get, "/1" ], [ :patch, "/1" ], [ :put, "/1" ], [ :delete, "/1" ] ].each do |method, suffix|
      assert_raises(ActionController::RoutingError) do
        Rails.application.routes.recognize_path("/api/v1/admin/users#{suffix}", method: method)
      end
    end
  end

  private

  def create_user(name)
    user = User.new(email: "#{name}@example.test", password: "password123", first_name: name, last_name: "Test", role: "member")
    user.skip_confirmation!
    user.save!
    user
  end

  def auth_headers(user)
    token = JWT.encode(
      { sub: user.id.to_s, jti: user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256"
    )
    { "Authorization" => "Bearer #{token}" }
  end
end
