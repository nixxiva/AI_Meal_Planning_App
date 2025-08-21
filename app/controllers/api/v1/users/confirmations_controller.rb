class Api::V1::Users::ConfirmationsController < Devise::ConfirmationsController
  # No longer need respond_to :json, as we're redirecting

  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      @token = generate_token(resource)
      redirect_to "http://localhost:3000/login?token=#{@token}"
    else
      redirect_to "http://localhost:3000/confirmation_error"
    end
  end

  private

  def generate_token(user)
    JWT.encode({ user_id: user.id }, Rails.application.credentials.devise_jwt_secret_key!, 'HS256')
  end

  