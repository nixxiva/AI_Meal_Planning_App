class ApplicationController < ActionController::API
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  protected

  def record_not_found
    render json: { error: "User not found" }, status: :not_found
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name email password role])
    devise_parameter_sanitizer.permit(:sign_in, keys: %i[email password])
  end

  def authenticate_user!
    token = request.headers["Authorization"]&.split(" ")&.last
    if token
      begin
        decoded_token = JWT.decode(token, Rails.application.credentials.devise_jwt_secret_key!, true, { algorithm: 'HS256' })
        user_id = decoded_token[0]["sub"]

        Rails.logger.debug("Decoded user_id: #{user_id}")
        @current_user = User.find(user_id)
      rescue JWT::DecodeError => e
        render json: { error: 'Invalid token' }, status: :unauthorized
      rescue ActiveRecord::RecordNotFound => e
        render json: {error: "User not found"}, status: :unauthorized
      end
    else
      render json: { error: 'Missing token' }, status: :unauthorized
    end
  end
end