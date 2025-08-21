module Api
  module V1
    class Users::SessionsController < Devise::SessionsController
      respond_to :json

      def create
        user_params = sign_in_params
        
        unless user_params
          render json: { message: 'Missing login parameters' }, status: :bad_request
          return
        end

        user = User.find_by(email: user_params[:email])

        if user.nil? || !user.valid_password?(user_params[:password])
          render json: { message: 'Invalid email or password' }, status: :unauthorized
          return
        end

        unless user.confirmed?
          render json: { message: 'Please confirm your email first to log in' }, status: :unauthorized
          return
        end

        if user.valid_password?(user_params[:password])
          sign_in(user)
          token = request.env['warden-jwt_auth.token']
          headers['Authorization'] = token

          render json: {
            status: {
              code: 200,
              message: 'Logged in successfully.',
              token: token,
              data: {
                user: UserSerializer.new(user).serializable_hash[:data][:attributes]
              }
            }
          }, status: :ok
        else
          render json: { message: 'Invalid email or password' }, status: :unauthorized
        end
      end
      
      private

      def sign_in_params
        params.require(:user).permit(:email, :password)
      end

      def respond_to_on_destroy
        if request.headers['Authorization'].present?
          begin
            jwt_payload = JWT.decode(request.headers['Authorization'].split.last,
                                     Rails.application.credentials.devise_jwt_secret_key!).first
            
            current_user = User.find_by(jti: jwt_payload['jti'])
          rescue JWT::DecodeError
            current_user = nil
          end
        end

        if current_user
          render json: {
            status: {
              code: 200,
              message: 'Logged out successfully.'
            }
          }, status: :ok
        else
          render json: {
            status: {
              code: 401,
              message: "Couldn't find an active session."
            }
          }, status: :unauthorized
        end
      end
    end
  end
end