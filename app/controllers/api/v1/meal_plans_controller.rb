class Api::V1::MealPlansController < ApplicationController
  before_action :authenticate_user!

  # GET /meal_plans
  def index
    meal_plans = current_user.meal_plans.includes(meal_plan_recipes: :recipe)
    render json: meal_plans.to_json(include: { meal_plan_recipes: { include: :recipe } })
  end

  # POST /meal_plans/generate
  def generate_1_day_plan
    meal_plan = MealPlanGeneratorService.new(current_user).generate_1_day_plan
    render json: meal_plan.to_json(include: { meal_plan_recipes: { include: :recipe } })
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
