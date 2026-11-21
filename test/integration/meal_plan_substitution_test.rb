require "test_helper"
require "minitest/mock"

class MealPlanSubstitutionTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "substitutions@example.test", password: "password123",
      first_name: "Meal", last_name: "Planner", role: "member")
    @user.skip_confirmation!
    @user.save!
    @user.allergies.create!(allergy_name: "Peanut")
    @user.disliked_ingredients.create!(ingredient_name: "Celery")
    @user.dietary_preferences.create!(pref_name: "Vegetarian")
    @rice = Ingredient.create!(ingredient_name: "rice", calories_per_gram: 1,
      protein_per_gram: 0, fat_per_gram: 0, carbs_per_gram: 1, serving_weight_grams: 100)
    NutritionService.stub(:new, nutrition_stub) do
      @user.pantry_items.create!(name: " Rice ", quantity: 100, unit: "g", ingredient: @rice)
    end
  end

  test "generation keeps response fields and requests one restricted suggestion per missing ingredient" do
    generate_with_substitute("Broccoli")
    assert_response :success
    assert_equal [ "carrot" ], @suggestion_calls
    assert_equal 1, @substitution_prompts.length
    assert_includes @substitution_prompts.first, "Peanut"
    assert_includes @substitution_prompts.first, "Celery"
    assert_includes @substitution_prompts.first, "Vegetarian"

    response_ingredients.each do |ingredient|
      assert ingredient.key?("from_pantry")
      assert ingredient.key?("substitute")
      if ingredient.fetch("ingredient").fetch("ingredient_name") == "rice"
        assert_equal true, ingredient.fetch("from_pantry")
        assert_nil ingredient.fetch("substitute")
      else
        assert_equal false, ingredient.fetch("from_pantry")
        assert_equal "Broccoli", ingredient.fetch("substitute")
      end
    end
  end

  test "known allergy and disliked suggestions are withheld after normalizing case and whitespace" do
    [ " PEANUT ", " celery " ].each do |suggestion|
      generate_with_substitute(suggestion)
      assert_response :success
      assert response_ingredients.all? { |ingredient| ingredient.fetch("substitute").nil? }
    end
  end

  test "blank suggestions remain unavailable without repeated provider requests" do
    generate_with_substitute("  ")
    assert_response :success
    assert_equal [ "carrot" ], @suggestion_calls
    assert response_ingredients.all? { |ingredient| ingredient.fetch("substitute").nil? }
  end

  test "substitution provider failure leaves the saved plan usable" do
    assert_difference "@user.meal_plans.count", 1 do
      generate_with_substitute(StandardError.new("Synthetic provider failure"))
      assert_response :success
    end
    assert_equal [ "carrot" ], @suggestion_calls
    assert_equal 3, response.parsed_body.fetch("meal_plan_recipes").length
    assert response_ingredients.all? { |ingredient| ingredient.fetch("substitute").nil? }
  end

  test "the AI adapter empty response sentinel remains unavailable" do
    generate_with_substitute("[]")
    assert_response :success
    assert_equal [ "carrot" ], @suggestion_calls
    assert response_ingredients.all? { |ingredient| ingredient.fetch("substitute").nil? }
  end

  private

  def generate_with_substitute(suggestion)
    @substitution_prompts = []
    @suggestion_calls = []
    ai = Object.new
    ai.define_singleton_method(:generate_meal_plan) do |prompt|
      if prompt.include?("Create a 1-day meal plan")
        %w[breakfast lunch dinner].map do |meal|
          { "meal_type" => meal, "recipe" => { "title" => "#{meal} bowl", "instructions" => "Cook",
            "ingredients" => [
              { "name" => "rice", "quantity" => 50, "unit" => "g" },
              { "name" => " CARROT ", "quantity" => 50, "unit" => "g" }
            ] } }
        end.to_json
      else
        @substitution_prompts << prompt
        raise suggestion if suggestion.is_a?(Exception)

        suggestion
      end
    end
    ai.instance_variable_set(:@substitution_prompts, @substitution_prompts)
    service = RecipeSuggestionService.new
    original = service.method(:suggest_substitute)
    calls = @suggestion_calls
    service.define_singleton_method(:suggest_substitute) do |name, **restrictions|
      calls << name
      original.call(name, **restrictions)
    end

    OpenaiService.stub(:new, ai) do
      NutritionService.stub(:new, nutrition_stub) do
        RecipeSuggestionService.stub(:new, service) do
          post "/api/v1/users/#{@user.id}/meal_plans/generate", headers: auth_headers, as: :json
        end
      end
    end
  end

  def nutrition_stub
    Object.new.tap do |service|
      service.define_singleton_method(:find_or_create_ingredient) do |name, *_amount|
        Ingredient.find_or_create_by!(ingredient_name: name.strip.downcase) do |ingredient|
          ingredient.calories_per_gram = 1
          ingredient.protein_per_gram = 0
          ingredient.fat_per_gram = 0
          ingredient.carbs_per_gram = 1
          ingredient.serving_weight_grams = 100
        end
      end
    end
  end

  def response_ingredients
    response.parsed_body.fetch("meal_plan_recipes").flat_map do |meal|
      meal.fetch("recipe").fetch("recipe_ingredients")
    end
  end

  def auth_headers
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "api_v1_user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
