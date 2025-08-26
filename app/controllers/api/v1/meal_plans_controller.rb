class Api::V1::MealPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  # POST /api/v1/users/:user_id/meal_plans/
  def create
    meal_plan = @user.meal_plans.build(meal_plan_params)
    
    if meal_plan.save
      render json: { message: "Meal plan created successfully", data: meal_plan}, status: :ok
    else
      render json: { errors: meal_plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/:user_id/meal_plans/:id
  def show
    meal_plan = @user.meal_plans.find(params[:id])

    if meal_plan
      render json: { status: 'success', data: meal_plan},status: :ok
    else 
      render json: { error: "Meal plan doesnt exist"},status: :not_found
    end
  end

  # Del /api/v1/users/:user_id/meal_plans/:id
  def destroy
    meal_plan = @current_user.meal_plans.find(params[:id])
    meal_plan.destroy
    render json: { status: 'success', message: "Meal plan deleted successfully" }, status: :ok
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def meal_plan_params
    params.require(:meal_plan).permit(:start_date, :end_date)
  end
end
