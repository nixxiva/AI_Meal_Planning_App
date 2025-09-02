class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers

  attr_reader :current_user
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  protected

  def record_not_found
    render json: { error: "Record not found" }, status: :not_found
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[first_name last_name email password role])
    devise_parameter_sanitizer.permit(:sign_in, keys: %i[email password])
  end

  def authenticate_user!
    Rails.logger.debug("Authorization Header: #{request.headers['Authorization']}")
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

  def authenticate_admin!
    authenticate_user!

    return if @current_user.nil?
    Rails.logger.error("No current user found.")

    unless @current_user.role == 'admin'
      render json: { error: 'Unauthorized - Admin access required' }, status: :unauthorized
      return
    end
  end

  def fetch_nutrition_data(query)
    begin
      nutritionix_credentials = Rails.application.credentials.nutritionix
    
      response = HTTParty.post(
        'https://trackapi.nutritionix.com/v2/natural/nutrients',
        headers: {
          'x-app-id' => nutritionix_credentials[:app_id],
          'x-app-key' => nutritionix_credentials[:app_key],
          'Content-Type' => 'application/json'
        },
        body: { query: query }.to_json
      )
      
      puts "Nutritionix API Response: #{response.body}"
      response.parsed_response
    rescue StandardError => e
      puts "Error fetching data from Nutritionix API: #{e.message}"
      nil
    end
  end
end
