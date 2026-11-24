require "test_helper"
require "minitest/mock"
require "stringio"

class TokenLifecycleTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "token-owner@example.test", password: "password123",
      first_name: "Token", last_name: "Owner", role: "member")
    @user.skip_confirmation!
    @user.save!
  end

  test "logout revokes the login token and a new login still works without cookies" do
    token = login_token
    request_plans(token)
    assert_response :success

    reset!
    delete "/api/v1/logout", headers: { "Authorization" => token }, as: :json
    assert_response :success

    request_plans(token)
    assert_response :unauthorized

    new_token = login_token
    request_plans(new_token)
    assert_response :success
    request_plans(token)
    assert_response :unauthorized
  end

  test "expired login tokens are rejected" do
    token = login_token
    travel 2.days do
      request_plans(token)
      assert_response :unauthorized
    end
  end

  test "missing and malformed tokens are rejected" do
    request_plans(nil)
    assert_response :unauthorized
    request_plans("Bearer invalid-token")
    assert_response :unauthorized
  end

  test "incorrect login credentials do not issue a token" do
    post "/api/v1/login", params: { user: { email: @user.email, password: "incorrect" } }, as: :json
    assert_response :unauthorized
    assert_nil response.headers["Authorization"]
  end

  test "authenticated requests do not write the bearer token to debug logs" do
    token = login_token
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    logger.level = Logger::DEBUG

    Rails.stub(:logger, logger) { request_plans(token) }

    assert_response :success
    refute_includes output.string, token.split.last
  end

  private

  def login_token
    reset!
    post "/api/v1/login", params: { user: { email: @user.email, password: "password123" } }, as: :json
    assert_response :success
    response.headers.fetch("Authorization").tap { |token| assert_match(/\ABearer \S+\z/, token) }
  end

  def request_plans(token)
    reset!
    headers = token ? { "Authorization" => token } : {}
    get "/api/v1/users/#{@user.id}/meal_plans", headers: headers, as: :json
  end
end
