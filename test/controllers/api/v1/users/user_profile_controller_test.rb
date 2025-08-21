require "test_helper"

class Api::V1::Users::UserProfileControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get api_v1_users_user_profile_show_url
    assert_response :success
  end

  test "should get update" do
    get api_v1_users_user_profile_update_url
    assert_response :success
  end
end
