class Api::V1::MealPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

    # GET /api/v1/users/:user_id/meal_plans
  def index
    meal_plans = @user.meal_plans.includes(meal_plan_recipes: :recipe)
    render json: meal_plans.to_json(include: { meal_plan_recipes: { include: :recipe } })
  end

    # POST /api/v1/users/:user_id/meal_plans
  def create
    meal_plan = @user.meal_plans.build(meal_plan_params)

    if meal_plan.save
      render json: { message: "Meal plan created successfully", data: meal_plan }, status: :ok
    else
      render json: { errors: meal_plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

    # GET /api/v1/users/:user_id/meal_plans/:id
  def show
    meal_plan = @user.meal_plans.find_by(id: params[:id])

    if meal_plan
      render json: { status: 'success', data: meal_plan }, status: :ok
    else
      render json: { error: "Meal plan doesn't exist" }, status: :not_found
    end
  end

  # DELETE /api/v1/users/:user_id/meal_plans/:id
  def destroy
    meal_plan = @user.meal_plans.find_by(id: params[:id])

    if meal_plan
      meal_plan.destroy
      render json: { status: 'success', message: "Meal plan deleted successfully" }, status: :ok
    else
      render json: { error: "Meal plan not found" }, status: :not_found
    end
  end

  # POST /api/v1/users/:user_id/meal_plans/generate
  def generate_1_day_plan
    meal_plan = MealPlanGeneratorService.new(@user).generate_1_day_plan
    render json: meal_plan.to_json(include: { meal_plan_recipes: { include: :recipe } })
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def meal_plan_params
    params.require(:meal_plan).permit(:start_date, :end_date)
  end
end
