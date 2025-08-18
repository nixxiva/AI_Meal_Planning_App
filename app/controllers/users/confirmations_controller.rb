class Users::ConfirmationsController < Devise::ConfirmationsController
  respond_to :json

  def show
    # Manually find user by confirmation token and confirm account
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      # If confirmation is successful, generate token
      @token = generate_token(resource)
      # Header not necessary as returning token in the response body
      # headers['Authorization'] = @token 

      render json: {
        status: {
          code: 200,
          message: 'Email confirmed successfully.',
          token: @token,
          data: UserSerializer.new(resource).serializable_hash[:data][:attributes]
        }
      }, status: :ok
    else
      render json: { error: 'Confirmation failed.' }, status: :unprocessable_entity
    end
  end

  private

  # Method to generate the JWT token
  def generate_token(user)
    JWT.encode({ user_id: user.id }, Rails.application.credentials.devise_jwt_secret_key!, 'HS256')
  end
end