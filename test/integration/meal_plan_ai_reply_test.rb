require "test_helper"
require "minitest/mock"

class MealPlanAiReplyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  PLAN_RECORD_COUNTS = [ "MealPlan.count", "Recipe.count", "MealPlanRecipe.count", "RecipeIngredient.count", "Ingredient.count" ].freeze

  setup do
    @user = User.new(email: "meal-plan-reply@example.test", password: "password123",
      first_name: "Meal", last_name: "Planner", role: "member")
    @user.skip_confirmation!
    @user.save!
    @rice = Ingredient.create!(ingredient_name: "rice", serving_weight_grams: 100,
      calories_per_gram: 1, protein_per_gram: 0, carbs_per_gram: 1, fat_per_gram: 0)
    @user.pantry_items.create!(ingredient: @rice, name: "rice", quantity: 500, unit: "g")
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    @headers = { "Authorization" => "Bearer #{token}" }
  end

  test "a plan returned at the provider token limit is discarded even when its JSON is complete" do
    assert_rejected(reply(finish_reason: "length"), "OpenAI returned an incomplete meal plan")
  end

  test "a completed plan is saved and returned" do
    assert_difference({ "MealPlan.count" => 1, "Recipe.count" => 3, "MealPlanRecipe.count" => 3 }) do
      generate_with(reply)
      assert_response :success
    end
    saved_plan = @user.meal_plans.find(response.parsed_body.fetch("id"))
    assert_equal %w[breakfast dinner lunch], saved_plan.meal_plan_recipes.pluck(:meal_type).sort
  end

  test "a refusal is reported without saving a plan" do
    provider_reply = reply
    provider_reply.dig("choices", 0)["message"] = { "refusal" => "Unable to fulfill the request", "content" => nil }

    assert_rejected(provider_reply, "OpenAI declined to generate a meal plan")
  end

  test "malformed content is still rejected after the provider reports completion" do
    provider_reply = reply
    provider_reply.dig("choices", 0, "message")["content"] = "Here are your meals: ["

    assert_rejected(provider_reply, "Meal plan must contain a complete breakfast, lunch and dinner")
  end

  test "a rate limit is reported without saving or retrying" do
    assert_rejected(Faraday::TooManyRequestsError.new, "OpenAI rate limit exceeded")
  end

  private

  def assert_rejected(provider_reply, error)
    assert_no_difference PLAN_RECORD_COUNTS do
      generate_with(provider_reply)
    end
    assert_response :unprocessable_entity
    assert_equal error, response.parsed_body.fetch("error")
  end

  def generate_with(provider_reply)
    calls = []
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      calls << parameters
      raise provider_reply if provider_reply.is_a?(Exception)

      provider_reply
    end
    OpenAI::Client.stub(:new, client) do
      post "/api/v1/users/#{@user.id}/meal_plans/generate", headers: @headers, as: :json
    end
    assert_equal 1, calls.size
    assert_equal "gpt-4o-mini", calls.sole.fetch(:model)
  end

  def reply(finish_reason: "stop")
    meals = %w[breakfast lunch dinner].map do |type|
      { meal_type: type, recipe: { title: "#{type} bowl", instructions: "Cook",
        ingredients: [ { name: "rice", quantity: 50, unit: "g" } ] } }
    end
    { "choices" => [ { "finish_reason" => finish_reason, "message" => { "content" => meals.to_json } } ] }
  end
end
