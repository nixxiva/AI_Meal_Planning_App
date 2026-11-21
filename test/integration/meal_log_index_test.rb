require "test_helper"

class MealLogIndexTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @owner = create_user("log-owner")
    @other = create_user("log-other")
    @recipe = @owner.recipes.create!(title: "Rice", instructions: "Cook")
  end

  test "index returns only the owner's logs newest first" do
    older = @owner.meal_logs.create!(recipe: @recipe, quantity: 1, date: 2.days.ago.to_date)
    newer = @owner.meal_logs.create!(recipe: @recipe, quantity: 2, date: Date.yesterday)
    other_recipe = @other.recipes.create!(title: "Soup", instructions: "Boil")
    @other.meal_logs.create!(recipe: other_recipe, quantity: 1, date: Date.current)

    get path(@owner), headers: auth_headers(@owner), as: :json
    assert_response :success
    assert_equal [ newer.id, older.id ], response.parsed_body.map { |log| log.fetch("id") }
    assert_equal [ 2.0, 1.0 ], response.parsed_body.map { |log| log.fetch("quantity") }
  end

  test "index rejects a URL for another account and requires authentication" do
    get path(@other), headers: auth_headers(@owner), as: :json
    assert_response :forbidden
    get path(@owner), as: :json
    assert_response :unauthorized
  end

  private

  def path(user)
    "/api/v1/users/#{user.id}/meal_logs"
  end

  def create_user(name)
    user = User.new(email: "#{name}@example.test", password: "password123", first_name: name, last_name: "Test", role: "member")
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
