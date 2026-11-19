class Api::V1::DietaryPreferencesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :require_confirmed_user!
  before_action :set_dietary_preference, only: :destroy

  def index
    render json: @user.dietary_preferences.order(:id).map { |item| item.attributes.slice("id", "pref_name") }
  end

  def create
    item = @user.dietary_preferences.new(dietary_preference_params)
    if item.save
      render json: item.attributes.slice("id", "pref_name"), status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @dietary_preference.destroy!
    head :no_content
  end

  private

  def set_user
    unless params[:user_id] == current_user.id.to_s
      render json: { error: "Unauthorized access" }, status: :forbidden
      return
    end
    @user = current_user
  end

  def require_confirmed_user!
    render json: { error: "User email not confirmed" }, status: :unauthorized unless current_user.confirmed?
  end

  def set_dietary_preference
    @dietary_preference = @user.dietary_preferences.find(params[:id])
  end

  def dietary_preference_params
    params.require(:dietary_preference).permit(:pref_name)
  end
end
