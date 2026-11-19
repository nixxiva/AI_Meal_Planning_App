class Api::V1::MealLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: :index
  before_action :set_meal_log, only: [:update, :destroy]
  before_action :load_today_logs, only: [:today, :today_totals]

  # GET /users/:user_id/meal_logs/today_totals
  def today_totals
    render json: calculate_daily_totals(@today_logs)
  end

  # GET /users/:user_id/meal_logs/today
  def today
    render json: calculate_today_meals(@today_logs)
  end

  # POST /users/:user_id/meal_logs
  def index
    render json: @user.meal_logs.includes(recipe: { recipe_ingredients: :ingredient }).order(date: :desc, id: :desc)
  end

  # POST /users/:user_id/meal_logs
  def create
    log = current_user.meal_logs.new(meal_log_params)
    log.date ||= Date.today
    if log.save
      render json: { success: true, meal_log: log }, status: :created
    else
      render json: { success: false, errors: log.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /users/:user_id/meal_logs/:id
  def update
    if @meal_log.update(meal_log_params)
      render json: { success: true, meal_log: @meal_log }
    else
      render json: { success: false, errors: @meal_log.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /users/:user_id/meal_logs/:id
  def destroy
    @meal_log.destroy
    render json: { success: true }
  end

  private

  def set_user
    unless params[:user_id] == current_user.id.to_s
      render json: { error: "Unauthorized access" }, status: :forbidden
      return
    end
    @user = current_user
  end

  def set_meal_log
    @meal_log = current_user.meal_logs.find(params[:id])
    rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: "Meal log not found" }, status: :not_found
  end
  
  def meal_log_params
    params.require(:meal_log).permit(:recipe_id, :quantity, :date)
  end
  
  def load_today_logs
    @today_logs = current_user.meal_logs.includes(recipe: { recipe_ingredients: :ingredient }).where(date: Date.today)
    errors = @today_logs.reject(&:valid?).flat_map do |log|
      log.errors.full_messages.map { |message| "Meal log #{log.id}: #{message}" }
    end
    render json: { success: false, errors: errors }, status: :unprocessable_entity if errors.any?
  end

  def calculate_daily_totals(logs)
    totals = { calories: 0, protein: 0, carbs: 0, fat: 0 }
    logs.each do |log|
      recipe = log.recipe
      next unless recipe
      nutrition = meal_nutrition(recipe, log.quantity)
      return totals.transform_values { nil }.merge(nutrition_available: false) unless nutrition[:nutrition_available]

      totals.each_key { |nutrient| totals[nutrient] += nutrition[nutrient] }
    end
    totals.merge(nutrition_available: true)
  end
  
  def calculate_today_meals(logs)
    logs.map do |log|
      {
        id: log.id,
        recipe_name: log.recipe&.title || "Unknown",
        quantity: log.quantity,
        macros: log.recipe ? meal_nutrition(log.recipe, log.quantity) : { calories: 0, protein: 0, carbs: 0, fat: 0 }
      }
    end
  end

  def meal_nutrition(recipe, servings)
    NutritionService.new.update_recipe_nutrition(recipe, servings: servings)
      .transform_keys { |key| key.to_s.delete_prefix("total_").to_sym }
  end
end
