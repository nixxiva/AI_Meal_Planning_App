module Api
  module V1    
    class Users::RegistrationsController < Devise::RegistrationsController
      respond_to :json

      before_action :sign_up_params, only: [:create]

      private

      def respond_with(resource, _opts = {})
        if resource.persisted?
          resource.send_confirmation_instructions

          render json: {
            status: { code: 200, message: 'Signed up successfully. Please confirm your email.',
                      token: @token,
                      data: UserSerializer.new(resource).serializable_hash[:data][:attributes] }
        }

        else
          render json: {
            status: { message: "User couldn't be created successfully. #{resource.errors.full_messages.to_sentence}" }
          }, status: :unprocessable_entity
        end
      end

      def sign_up_params
        params.require(:registration).require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name, :role)
      end
    end
  end
end

