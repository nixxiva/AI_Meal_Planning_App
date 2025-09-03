class Api::V1::MealLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_meal_log, only: [:update, :destroy]

  # GET /users/:user_id/meal_logs/today_totals
  def today_totals
    render json: calculate_daily_totals(current_user)
  end

  # GET /users/:user_id/meal_logs/today
  def today
    render json: calculate_today_meals(current_user)
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

  def set_meal_log
    @meal_log = current_user.meal_logs.find(params[:id])
    rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: "Meal log not found" }, status: :not_found
  end
  
  def meal_log_params
    params.require(:meal_log).permit(:recipe_id, :quantity, :date)
  end
  
  def calculate_daily_totals(user, date = Date.today)
    logs = user.meal_logs.includes(:recipe).where(date: date)
    totals = { calories: 0, protein: 0, carbs: 0, fat: 0 }
    logs.each do |log|
      recipe = log.recipe
      next unless recipe
      recipe.ingredients.each do |ing|
        quantity = log.quantity || 1
        totals[:calories] += (ing.calories_per_gram * ing.serving_weight_grams * quantity)
        totals[:protein]  += (ing.protein_per_gram  * ing.serving_weight_grams * quantity)
        totals[:carbs]    += (ing.carbs_per_gram    * ing.serving_weight_grams * quantity)
        totals[:fat]      += (ing.fat_per_gram      * ing.serving_weight_grams * quantity)
      end
    end
    totals
  end
  
  def calculate_today_meals(user, date = Date.today)
    user.meal_logs.includes(:recipe).where(date: date).map do |log|
      {
        id: log.id,
        recipe_name: log.recipe&.title || "Unknown",
        quantity: log.quantity,
        macros: log.recipe ? log.recipe.ingredients.each_with_object({ calories: 0, protein: 0, carbs: 0, fat: 0 }) { |ing, h|
          h[:calories] += ing.calories_per_gram * ing.serving_weight_grams * log.quantity
          h[:protein]  += ing.protein_per_gram  * ing.serving_weight_grams * log.quantity
          h[:carbs]    += ing.carbs_per_gram    * ing.serving_weight_grams * log.quantity
          h[:fat]      += ing.fat_per_gram      * ing.serving_weight_grams * log.quantity
        } : { calories: 0, protein: 0, carbs: 0, fat: 0 }
      }
    end
  end
end
