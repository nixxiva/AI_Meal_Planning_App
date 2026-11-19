require "test_helper"

class SignupRoleTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "public signup assigns member even when admin is requested" do
    assert_member_signup(role: "admin")
  end

  test "public signup assigns member when role is omitted" do
    assert_member_signup
  end

  private

  def assert_member_signup(**extra)
    attributes = { email: "signup@example.test", first_name: "Test", last_name: "Member",
                   password: "password123", password_confirmation: "password123" }.merge(extra)
    assert_difference("User.count", 1) do
      post "/api/v1/signup", params: { registration: { user: attributes } }, as: :json
      assert_response :success
    end
    assert_equal "member", User.find_by!(email: attributes[:email]).role
  end
end
