require "test_helper"

class AccountEndpointsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = create_user("account-owner")
    @other = create_user("account-other")
  end

  test "account and profile GET expose the same explicit account fields" do
    @user.update!(health_goal: HealthGoal.create!(goal_name: "Maintain weight"))
    @user.allergies.create!(allergy_name: "Peanut")
    @user.disliked_ingredients.create!(ingredient_name: "Celery")
    @user.dietary_preferences.create!(pref_name: "Vegetarian")

    account_paths.each do |path|
      get path, headers: auth_headers(@user), as: :json
      assert_response :success
      assert_account_response
    end
  end

  test "account without a health goal returns null and empty nested collections" do
    get account_paths.first, headers: auth_headers(@user), as: :json
    assert_response :success
    assert_account_response
    assert_nil response.parsed_body.fetch("health_goal")
  end

  test "both GET endpoints require a valid token and confirmed account" do
    account_paths.each do |path|
      get path, as: :json
      assert_response :unauthorized
      get path, headers: { "Authorization" => "Bearer invalid-token" }, as: :json
      assert_response :unauthorized
    end

    @user.update_columns(confirmed_at: nil)
    account_paths.each do |path|
      get path, headers: auth_headers(@user), as: :json
      assert_response :unauthorized
    end
    patch profile_path, params: { user: { first_name: "Changed" } }, headers: auth_headers(@user), as: :json
    assert_response :unauthorized
    assert_equal "account-owner", @user.reload.first_name
  end

  test "URL IDs must exactly match the authenticated account on GET and PATCH" do
    [@other.id.to_s, "0", "#{@user.id}junk", "0#{@user.id}"].each do |id|
      ["/api/v1/users/#{id}", "/api/v1/users/#{id}/user_profile"].each do |path|
        get path, headers: auth_headers(@user), as: :json
        assert_response :forbidden, path
      end
      patch "/api/v1/users/#{id}/user_profile", params: { user: { first_name: "Changed" } },
        headers: auth_headers(@user), as: :json
      assert_response :forbidden
    end
    assert_equal "account-owner", @user.reload.first_name
    assert_equal "account-other", @other.reload.first_name
  end

  test "profile PATCH creates updates and deletes nested preferences with the same response contract" do
    goal = HealthGoal.create!(goal_name: "Build muscle")
    patch_profile(first_name: "Updated", health_goal_id: goal.id,
      allergies_attributes: [{ allergy_name: "Peanut" }],
      disliked_ingredients_attributes: [{ ingredient_name: "Celery" }],
      dietary_preferences_attributes: [{ pref_name: "Vegetarian" }])
    assert_equal "Updated", @user.reload.first_name
    assert_equal goal.id, @user.health_goal_id
    allergy = @user.allergies.sole
    dislike = @user.disliked_ingredients.sole
    preference = @user.dietary_preferences.sole

    patch_profile(allergies_attributes: [{ id: allergy.id, allergy_name: "Milk" }],
      disliked_ingredients_attributes: [{ id: dislike.id, ingredient_name: "Onion" }],
      dietary_preferences_attributes: [{ id: preference.id, pref_name: "Vegan" }])
    assert_equal "Milk", allergy.reload.allergy_name
    assert_equal "Onion", dislike.reload.ingredient_name
    assert_equal "Vegan", preference.reload.pref_name

    patch_profile(health_goal_id: nil,
      allergies_attributes: [{ id: allergy.id, _destroy: true }],
      disliked_ingredients_attributes: [{ id: dislike.id, _destroy: true }],
      dietary_preferences_attributes: [{ id: preference.id, _destroy: true }])
    assert_empty @user.allergies.reload
    assert_empty @user.disliked_ingredients.reload
    assert_empty @user.dietary_preferences.reload
    assert_nil @user.reload.health_goal
  end

  private

  def create_user(name)
    user = User.new(email: "#{name}@example.test", password: "password123",
      first_name: name, last_name: "Test", role: "member")
    user.skip_confirmation!
    user.save!
    user
  end

  def account_paths
    ["/api/v1/users/#{@user.id}", profile_path]
  end

  def profile_path
    "/api/v1/users/#{@user.id}/user_profile"
  end

  def auth_headers(user)
    token = JWT.encode({ sub: user.id.to_s, jti: user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def patch_profile(attributes)
    patch profile_path, params: { user: attributes }, headers: auth_headers(@user), as: :json
    assert_response :success
    assert_account_response
  end

  def assert_account_response
    @user.reload
    expected = @user.attributes.slice("id", "first_name", "last_name", "email", "role", "health_goal_id")
    expected["allergies"] = @user.allergies.order(:id).map { |record| record.attributes.slice("id", "allergy_name") }
    expected["disliked_ingredients"] = @user.disliked_ingredients.order(:id).map { |record| record.attributes.slice("id", "ingredient_name") }
    expected["dietary_preferences"] = @user.dietary_preferences.order(:id).map { |record| record.attributes.slice("id", "pref_name") }
    expected["health_goal"] = @user.health_goal&.attributes&.slice("id", "goal_name")
    assert_equal expected, response.parsed_body
  end
end
