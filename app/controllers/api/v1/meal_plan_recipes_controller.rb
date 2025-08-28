class Api::V1::MealPlanRecipesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :set_meal_plan

  # POST /api/v1/users/:user_id/meal_plans/:meal_plan_id/meal_plan_recipes
  def create
    recipe = Recipe.find_by(id: params[:meal_plan_recipe][:recipe_id])

    if recipe.nil?
      render json: { status: 'error', message: 'Recipe not found' }, status: :not_found
      return
    end

    existing_meal_plan_recipe = MealPlanRecipe.find_by(meal_plan_id: @meal_plan.id, recipe_id: recipe.id)

    if existing_meal_plan_recipe
      render json: { status: 'error', message: 'Recipe already added to this meal plan.' }, status: :unprocessable_entity
      return
    end

    meal_plan_recipe = @meal_plan.meal_plan_recipes.create(recipe_id: recipe.id)

    if meal_plan_recipe.persisted?
      render json: { status: 'success', message: 'Recipe added to meal plan successfully', data: meal_plan_recipe }, status: :created
    else
      render json: { status: 'error', errors: meal_plan_recipe.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DEL /api/v1/users/:user_id/meal_plans/:meal_plan_id/meal_plan_recipes/:id
  def destroy
  meal_plan_recipe = @meal_plan.meal_plan_recipes.find_by(id: params[:id])

  if meal_plan_recipe
    meal_plan_recipe.destroy
    render json: { status: 'success', message: 'Recipe removed from meal plan successfully' }, status: :ok
  else
    render json: { status: 'error', message: 'Meal plan recipe not found' }, status: :not_found
  end
end

  private
  
  def set_user
    @user = User.find(params[:user_id])
  end

  def set_meal_plan
    @meal_plan = @user.meal_plans.find_by(id: params[:meal_plan_id])

    if @meal_plan.nil?
      render json: { status: 'error', message: 'Meal plan not found or not accessible by current user' }, status: :not_found
    end
  end
end
