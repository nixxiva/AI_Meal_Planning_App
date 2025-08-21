module Api
  module V1
    module Users
      class UserProfilesController < ApplicationController
        before_action :authenticate_user!
        before_action :set_user, only: [:show, :update, :destroy]

        def show
          if @user.confirmed?
            render json: @user, include: [:dietary_preferences, :health_goal, :allergies, :disliked_ingredients]
          else
            render json: {error: "User email not confirmed."}, status: :unauthorized
          end
        end

        def update
          if @user.confirmed?
            if @user.update(user_profile_params)
              render json: @user, include: [:dietary_preferences, :health_goal, :allergies, :disliked_ingredients]
            else
              render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
            end
          else
            render json: {error: "User email not confirmed"}, status: :unauthorized
          end
        end

        def destroy
          @user.destroy
          render json: {message: "User successfully deleted"}
        end

        private

        def set_user
          @user = User.find(params[:user_id])
        end

        def user_profile_params
          params.require(:user).permit(
            :first_name,
            :last_name,
            :email,
            :health_goal_id,
            allergies_attributes: [:id, :allergy_name, :_destroy],
            disliked_ingredients_attributes: [:id, :ingredient_name, :_destroy],
            dietary_preferences_attributes: [:id, :pref_name, :_destroy]
          )
        end
      end
    end
  end
end