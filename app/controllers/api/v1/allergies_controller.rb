class Api::V1::AllergiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :require_confirmed_user!
  before_action :set_allergy, only: :destroy

  def index
    render json: @user.allergies.order(:id).map { |item| item.attributes.slice("id", "allergy_name") }
  end

  def create
    item = @user.allergies.new(allergy_params)
    if item.save
      render json: item.attributes.slice("id", "allergy_name"), status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @allergy.destroy!
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

  def set_allergy
    @allergy = @user.allergies.find(params[:id])
  end

  def allergy_params
    params.require(:allergy).permit(:allergy_name)
  end
end
