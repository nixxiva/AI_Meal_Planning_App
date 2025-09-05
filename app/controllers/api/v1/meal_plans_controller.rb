class Api::V1::MealPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :set_meal_plan, only: [:show, :destroy]

    # GET /api/v1/users/:user_id/meal_plans
  def index
    render json: render_meal_plan(@user.meal_plans.includes(meal_plan_recipes: { recipe: { recipe_ingredients: :ingredient } }))
  end

    # POST /api/v1/users/:user_id/meal_plans
  def create
    meal_plan = @user.meal_plans.build(meal_plan_params)

    if meal_plan.save
      render json: { message: "Meal plan created successfully", data: render_meal_plan(meal_plan) }, status: :ok
    else
      render json: { errors: meal_plan.errors.full_messages }, status: :unprocessable_entity
    end
  end

    # GET /api/v1/users/:user_id/meal_plans/:id
  def show
    if meal_plan
      render json: { status: 'success', data: render_meal_plan(meal_plan) }, status: :ok
    else
      render json: { error: "Meal plan doesn't exist" }, status: :not_found
    end
  end

    # DELETE /api/v1/users/:user_id/meal_plans/:id
  def destroy
    if meal_plan
      meal_plan.destroy
      render json: { status: 'success', message: "Meal plan deleted successfully" }, status: :ok
    else
      render json: { error: "Meal plan not found" }, status: :not_found
    end
  end

    # POST /api/v1/users/:user_id/meal_plans/generate
  def generate
    meal_plan = MealPlanGeneratorService.new(@user).generate_1_day_plan
    render json: render_meal_plan(meal_plan)
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

  def set_meal_plan
    @meal_plan = @user.meal_plans.find_by(id: params[:id])
  end

  def meal_plan_json_options
    {
      include: {
        meal_plan_recipes: {
          include: {
            recipe: {
              include: { recipe_ingredients: { include: :ingredient } }
            }
          },
          methods: [:meal_type]
        }
      }
    }
  end

  def render_meal_plan(meal_plan_or_relation)
    json = meal_plan_or_relation.as_json(meal_plan_json_options)

    # handle single record or collection
    [json].flatten.each do |mp|
      next unless mp['meal_plan_recipes']

      mp['meal_plan_recipes'].each do |mpr|
        # map integer to enum string
        mpr['meal_type'] = MealPlanRecipe.meal_types.key(mpr['meal_type'].to_i) if mpr['meal_type']
      end
    end

    json
  end
end
