require "test_helper"
require "minitest/mock"

class Api::V1::PantryItemsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.new(email: "pantry-quantity@example.test", password: "password123",
      first_name: "Pantry", last_name: "Test", role: "member")
    @user.skip_confirmation!
    @user.save!
    @ingredient = Ingredient.create!(ingredient_name: "rice", serving_weight_grams: 100,
      calories_per_gram: 1, protein_per_gram: 0, carbs_per_gram: 1, fat_per_gram: 0)
    token = JWT.encode({ sub: @user.id.to_s, jti: @user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    @headers = { "Authorization" => "Bearer #{token}" }
    @path = "/api/v1/users/#{@user.id}/pantry_items"
  end

  test "create rejects invalid quantities without adding stock" do
    [ "oops", "12oops", "", -1, "-1e-999", "1e-999", "1e999", true, [ 1 ], { amount: 1 } ].each do |amount|
      assert_no_difference [ "PantryItem.count", "Ingredient.count" ] do
        post @path, params: { pantry_item: { name: "rice", quantity: amount, unit: "g" } },
          headers: @headers, as: :json
        assert_quantity_error
      end
    end
  end

  test "update rejects a malformed quantity and retains all saved attributes" do
    item = create_stock
    original = item.attributes

    patch "#{@path}/#{item.id}", params: { pantry_item: { quantity: "12oops", unit: "kg" } },
      headers: @headers, as: :json

    assert_quantity_error
    assert_equal original, item.reload.attributes
  end

  test "invalid quantity is rejected before looking up an ingredient" do
    item = create_stock
    no_lookup = ->(*) { flunk "Invalid stock should not trigger a nutrition lookup" }
    attributes = { pantry_item: { name: "untracked rice", quantity: "oops", unit: "g" } }

    NutritionService.stub(:new, no_lookup) do
      post @path, params: attributes, headers: @headers, as: :json
      assert_quantity_error

      patch "#{@path}/#{item.id}", params: attributes, headers: @headers, as: :json
      assert_quantity_error
    end
  end

  {
    "trailing underscore" => "12_".to_json,
    "embedded null character" => "12\0oops".to_json,
    "trailing null character" => "12\0".to_json,
    "huge quoted exponent" => "1e-99999999999999999999".to_json,
    "positive JSON underflow" => "1e-999",
    "negative JSON underflow" => "-1e-999",
    "JSON overflow" => "1e999"
  }.each do |label, token|
    test "#{label} is rejected before pantry or ingredient writes" do
      item = create_stock
      original = item.attributes
      patch "#{@path}/#{item.id}", **raw_json(%({"pantry_item":{"quantity":#{token},"unit":"kg"}}))
      assert_quantity_error
      assert_equal original, item.reload.attributes

      payload = %({"pantry_item":{"name":"untracked rice","quantity":#{token},"unit":"g"}})
      no_lookup = ->(*) { flunk "Invalid stock should not trigger a nutrition lookup" }
      NutritionService.stub(:new, no_lookup) do
        assert_no_difference [ "PantryItem.count", "Ingredient.count" ] do
          post @path, **raw_json(payload)
          assert_quantity_error
        end
      end
    end
  end

  test "create accepts zero and valid numeric strings and keeps omitted stock unknown" do
    [ { quantity: 0 }, { quantity: "0" }, { quantity: "2.5" }, { quantity: " +.25e2 " }, {}, { quantity: nil } ].each do |amount|
      post @path, params: { pantry_item: { name: "rice", unit: "g" }.merge(amount) },
        headers: @headers, as: :json
      assert_response :created
      saved = @user.pantry_items.find(response.parsed_body.fetch("id"))
      if amount[:quantity].nil?
        assert_nil saved.quantity
      else
        assert_equal amount[:quantity].to_f, saved.quantity
      end
    end
  end

  test "update accepts a numeric zero string and retains it in a partial update" do
    item = create_stock

    patch "#{@path}/#{item.id}", params: { pantry_item: { quantity: "0" } }, headers: @headers, as: :json
    assert_response :success
    assert_equal 0, item.reload.quantity

    patch "#{@path}/#{item.id}", params: { pantry_item: { unit: "kg" } }, headers: @headers, as: :json
    assert_response :success
    assert_equal 0, item.reload.quantity
    assert_equal "kg", item.unit
  end

  test "nested JSON accepts true zero and ordinary decimals before saving" do
    { "-0.0" => 0.0, "2.5e1" => 25.0 }.each do |token, quantity|
      post @path, **raw_json(%({"pantry_item":{"name":"rice","quantity":#{token},"unit":"g"}}))
      assert_response :created
      saved = @user.pantry_items.find(response.parsed_body.fetch("id"))
      assert_equal quantity, saved.quantity
    end
  end

  test "wrapped JSON keeps true zero and validates the body quantity ahead of a flat query quantity" do
    item = create_stock
    path = "#{@path}/#{item.id}"

    patch path, **raw_json('{"quantity":0e999999}')
    assert_response :ok
    assert_equal 0.0, item.reload.quantity

    patch "#{path}?quantity=7", **raw_json('{"quantity":1e-999,"unit":"kg"}')
    assert_quantity_error
    assert_equal [ 0.0, "g" ], item.reload.attributes.values_at("quantity", "unit")
  end

  test "the nested query object overrides the JSON body and omission retains stock" do
    item = create_stock
    path = "#{@path}/#{item.id}"

    patch "#{path}?pantry_item%5Bquantity%5D=7", **raw_json('{"pantry_item":{"quantity":1e-999}}')
    assert_response :ok
    assert_equal 7.0, item.reload.quantity

    patch "#{path}?pantry_item%5Bunit%5D=kg", **raw_json('{"pantry_item":{"quantity":0.0}}')
    assert_response :ok
    assert_equal [ 7.0, "kg" ], item.reload.attributes.values_at("quantity", "unit")
  end

  test "a form quantity accepts scientific notation and nested JSON null stays omitted" do
    item = create_stock
    path = "#{@path}/#{item.id}"

    put path, params: { pantry_item: { quantity: "2.5e1" } }, headers: @headers
    assert_response :ok
    assert_equal 25.0, item.reload.quantity

    patch path, **raw_json('{"pantry_item":{"quantity":null,"unit":"kg"},"quantity":1e-999}')
    assert_response :ok
    assert_equal [ 25.0, "kg" ], item.reload.attributes.values_at("quantity", "unit")
  end

  private

  def raw_json(body)
    { params: body, headers: @headers.merge("CONTENT_TYPE" => "application/json") }
  end

  def create_stock
    @user.pantry_items.create!(ingredient: @ingredient, name: "rice", quantity: 50, unit: "g")
  end

  def assert_quantity_error
    assert_response :unprocessable_entity
    assert_match(/quantity/i, response.parsed_body.to_json)
  end
end
