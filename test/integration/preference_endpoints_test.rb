require "test_helper"

class PreferenceEndpointsTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  RESOURCES = [
    [:allergies, :allergy, :allergy_name, true],
    [:dietary_preferences, :dietary_preference, :pref_name, true],
    [:disliked_ingredients, :disliked_ingredient, :ingredient_name, false]
  ].freeze

  setup do
    @owner = create_user("owner")
    @other = create_user("other")
    @unconfirmed = create_user("unconfirmed", confirmed: false)
  end

  RESOURCES.each do |collection, envelope, field, listable|
    test "#{collection} creates a named record owned by the authenticated user" do
      foreign = @other.public_send(collection).create!(field => "Foreign")
      assert_difference -> { @owner.public_send(collection).count }, 1 do
        post path(@owner, collection), params: { envelope => { field => "New", user_id: @other.id, id: foreign.id }, user_id: @other.id }, headers: auth_headers(@owner), as: :json
        assert_response :created
      end
      record = @owner.public_send(collection).find_by!(field => "New")
      assert_equal record.id, response.parsed_body.fetch("id")
      assert_equal "New", response.parsed_body.fetch(field.to_s)
      assert_equal @other.id, foreign.reload.user_id
      assert_equal "Foreign", foreign.public_send(field)
      assert_equal 1, @other.public_send(collection).count
    end

    test "#{collection} rejects blank and duplicate names without saving" do
      @owner.public_send(collection).create!(field => "Existing")
      ["", "   ", "Existing"].each do |name|
        assert_no_difference -> { @owner.public_send(collection).count } do
          post path(@owner, collection), params: { envelope => { field => name } }, headers: auth_headers(@owner), as: :json
          assert_response :unprocessable_entity
        end
      end
    end

    test "#{collection} deletes an owned record" do
      record = @owner.public_send(collection).create!(field => "Owned")
      assert_difference -> { @owner.public_send(collection).count }, -1 do
        delete "#{path(@owner, collection)}/#{record.id}", headers: auth_headers(@owner), as: :json
        assert_response :no_content
        assert_empty response.body
      end
    end

    test "#{collection} cannot delete another users child through the owners URL" do
      record = @other.public_send(collection).create!(field => "Foreign")
      assert_no_difference -> { record.class.count } do
        delete "#{path(@owner, collection)}/#{record.id}", headers: auth_headers(@owner), as: :json
        assert_response :not_found
      end
      assert_equal @other.id, record.reload.user_id
    end

    actions = listable ? [:get, :post, :delete] : [:post, :delete]
    actions.each do |action|
      test "#{collection} #{action} rejects another users URL" do
        record = @other.public_send(collection).create!(field => "Foreign")
        assert_no_difference -> { record.class.count } do
          endpoint = path(@other, collection)
          endpoint += "/#{record.id}" if action == :delete
          public_send action, endpoint, params: { envelope => { field => "Attempt" } }, headers: auth_headers(@owner), as: :json
          assert_response :forbidden
        end
        assert_equal "Foreign", record.reload.public_send(field)
        assert_equal @other.id, record.user_id
      end

      [:missing, :unconfirmed].each do |identity|
        test "#{collection} #{action} rejects #{identity} authentication" do
          user = identity == :unconfirmed ? @unconfirmed : @owner
          record = user.public_send(collection).create!(field => "Existing")
          headers = identity == :missing ? {} : auth_headers(user)
          assert_no_difference -> { record.class.count } do
            endpoint = path(user, collection)
            endpoint += "/#{record.id}" if action == :delete
            public_send action, endpoint, params: { envelope => { field => "Attempt" } }, headers: headers, as: :json
            assert_response :unauthorized
          end
          assert_equal "Existing", record.reload.public_send(field)
        end
      end
    end

    if listable
      test "#{collection} lists only the owners records as an array" do
        owned = @owner.public_send(collection).create!(field => "Owned")
        @other.public_send(collection).create!(field => "Foreign")
        get path(@owner, collection), headers: auth_headers(@owner), as: :json
        assert_response :success
        assert_kind_of Array, response.parsed_body
        assert_equal [owned.id], response.parsed_body.map { |record| record.fetch("id") }
        assert_equal ["Owned"], response.parsed_body.map { |record| record.fetch(field.to_s) }
      end
    end
  end

  private

  def create_user(name, confirmed: true)
    user = User.new(email: "preferences-#{name}@example.test", password: "password123",
      first_name: name, last_name: "Test", role: "member")
    user.skip_confirmation! if confirmed
    user.save!
    user
  end

  def path(user, collection)
    "/api/v1/users/#{user.id}/#{collection}"
  end

  def auth_headers(user)
    token = JWT.encode({ sub: user.id.to_s, jti: user.jti, scp: "user", exp: 1.hour.from_now.to_i },
      Rails.application.credentials.devise_jwt_secret_key!, "HS256")
    { "Authorization" => "Bearer #{token}" }
  end
end
