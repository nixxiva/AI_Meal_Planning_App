class Api::V1::DislikedIngredientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :require_confirmed_user!
  before_action :set_disliked_ingredient, only: :destroy

  def create
    item = @user.disliked_ingredients.new(disliked_ingredient_params)
    if item.save
      render json: item.attributes.slice("id", "ingredient_name"), status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @disliked_ingredient.destroy!
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

  def set_disliked_ingredient
    @disliked_ingredient = @user.disliked_ingredients.find(params[:id])
  end

  def disliked_ingredient_params
    params.require(:disliked_ingredient).permit(:ingredient_name)
  end
end
