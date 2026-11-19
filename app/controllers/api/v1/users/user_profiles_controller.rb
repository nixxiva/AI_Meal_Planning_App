module Api
  module V1
    module Users
      class UserProfilesController < ApplicationController
        before_action :authenticate_user!
        before_action :set_user, only: [:show, :update, :destroy]
        before_action :require_confirmed_user, only: [:show, :update]

        def show
          render json: profile_json
        end

        def update
          if @user.update(user_profile_params)
            render json: profile_json
          else
            render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          @user.destroy
          render json: {message: "User successfully deleted"}
        end

        private

        def set_user
          user_id = params[:user_id] || params[:id]
          unless user_id == current_user.id.to_s
            render json: { error: "Unauthorized access" }, status: :forbidden
            return
          end

          @user = current_user
        end

        def require_confirmed_user
          render json: { error: "User email not confirmed" }, status: :unauthorized unless @user.confirmed?
        end

        def profile_json
          @user.attributes.slice("id", "first_name", "last_name", "email", "role", "health_goal_id").merge(
            "health_goal" => @user.health_goal&.attributes&.slice("id", "goal_name"),
            "allergies" => @user.allergies.order(:id).map { |record| record.attributes.slice("id", "allergy_name") },
            "disliked_ingredients" => @user.disliked_ingredients.order(:id).map { |record| record.attributes.slice("id", "ingredient_name") },
            "dietary_preferences" => @user.dietary_preferences.order(:id).map { |record| record.attributes.slice("id", "pref_name") }
          )
        end

        def user_profile_params
          params.require(:user).permit(
            :first_name, 
            :last_name, 
            :email, 
            :health_goal_id,
            allergies_attributes: [:id, :allergy_name, :ingredient_name, :_destroy],
            disliked_ingredients_attributes: [:id, :ingredient_name, :_destroy],
            dietary_preferences_attributes: [:id, :pref_name, :_destroy]
          )
        end
      end
    end
  end
end
