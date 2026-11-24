require "bigdecimal"

class Api::V1::RecipesController < ApplicationController
  NUTRITION_TARGET_TOTALS = {
    target_calories: :total_calories,
    target_protein: :total_protein,
    target_carbs: :total_carbs,
    target_fat: :total_fat
  }.freeze
  NUTRITION_TARGET_TOLERANCE = BigDecimal("0.02")

  before_action :authenticate_user!
  before_action :set_recipe, only: [ :show, :rate, :adjust, :update, :destroy ]
  before_action :check_recipe_ownership, only: [ :update, :destroy, :adjust ]

  # GET /api/v1/recipes
  def index
    recipes = filter_recipes(@current_user.recipes).to_a
    render json: { data: { recipes: recipe_summaries(recipes), total: recipes.size } }
  end

  # GET /api/v1/recipes/:id
  def show
    render json: { data: { recipe: detailed_recipe_json(@recipe) } }
  end

  # POST /api/v1/recipes
  def create
    @recipe = @current_user.recipes.build(recipe_params)
    ingredients = prepare_recipe_ingredients
    saved = Recipe.transaction do
      if @recipe.save
        create_recipe_ingredients(ingredients)
        true
      end
    end
    if saved
      render json: success_response("Recipe created successfully", @recipe)
    else
      render json: { errors: @recipe.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/recipes/:id
  def update
    ingredients = prepare_recipe_ingredients
    saved = Recipe.transaction do
      if @recipe.update(recipe_params)
        update_recipe_ingredients(ingredients) if ingredients.present?
        true
      end
    end
    if saved
      render json: success_response("Recipe updated successfully", @recipe)
    else
      render json: { errors: @recipe.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/recipes/:id
  def destroy
    @recipe.destroy
    render json: { status: "success", message: "Recipe deleted successfully" }
  end

  # POST /api/v1/recipes/:id/rate
  def rate
    rating = @recipe.ratings.find_or_initialize_by(user: @current_user)
    if rating.update(rating: rating_params[:rating])
      render json: { status: "success", message: "Recipe rated successfully", data: recipe_summaries([ @recipe ]).sole }
    else
      render json: { status: "error", errors: rating.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/recipes/:id/adjust
  def adjust
    target_nutrition = nutrition_params
    unless target_nutrition
      return render json: { status: "error", message: "Nutrition targets must be finite, nonnegative numbers" },
        status: :unprocessable_entity
    end

    adjusted_recipe = RecipeAdjustmentService.new(@recipe, @current_user).adjust_recipe(target_nutrition)
    result = success_response("Recipe adjusted successfully", adjusted_recipe)
    if target_nutrition.present?
      result[:data][:target_status] = adjustment_target_status(target_nutrition, result[:data])
    end
    render json: result
  rescue => e
    Rails.logger.error "Recipe adjustment error: #{e.message}"
    render json: { status: "error", message: "Failed to adjust recipe" }, status: :unprocessable_entity
  end

  private

  def set_recipe
    @recipe = Recipe.find_by(id: params[:id])
    render json: { status: "error", message: "Recipe not found" }, status: :not_found unless @recipe
  end

  def check_recipe_ownership
    render json: { status: "error", message: "Unauthorized access" }, status: :forbidden unless @recipe.user == @current_user
  end

  def recipe_params
    params.require(:recipe).permit(:title, :instructions)
  end

  def recipe_ingredients_params
    params.require(:recipe).permit(recipe_ingredients: [ :ingredient_name, :quantity, :unit ])[:recipe_ingredients] || []
  end

  def rating_params
    params.require(:rating).permit(:rating)
  end

  def nutrition_params
    NUTRITION_TARGET_TOTALS.each_key.with_object({}) do |key, targets|
      next unless params.key?(key)

      value = params[key]
      return unless value.is_a?(Numeric) || value.is_a?(String)

      target = BigDecimal(value.to_s, exception: false)
      return unless target&.finite? && target >= 0

      numeric = target.to_f
      return unless numeric.finite? && (target.zero? || numeric.positive?)

      targets[key] = target
    end
  end

  def adjustment_target_status(targets, nutrition)
    return "unavailable" unless nutrition.fetch(:nutrition_available)

    matches = targets.map do |key, target|
      total = BigDecimal(nutrition.fetch(NUTRITION_TARGET_TOTALS.fetch(key)).to_s, exception: false)
      return "unavailable" unless total&.finite?

      (total - target).abs <= target * NUTRITION_TARGET_TOLERANCE
    end
    matches.all? ? "met" : "missed"
  end

  def filter_recipes(recipes)
    recipes = filter_by_ingredient(recipes) if params[:ingredient].present?
    recipes = filter_by_search(recipes) if params[:search].present?
    recipes
  end

  def filter_by_ingredient(recipes)
    matching_ingredients = RecipeIngredient.joins(:ingredient).where(ingredients: { ingredient_name: params[:ingredient] })
    recipes.where(id: matching_ingredients.select(:recipe_id))
  end

  def filter_by_search(recipes)
    recipes.where("title ILIKE ?", "%#{params[:search]}%")
  end

  def prepare_recipe_ingredients
    return [] if recipe_ingredients_params.empty?

    nutrition_service = NutritionService.new
    recipe_ingredients_params.map do |ingredient_data|
      ingredient = nutrition_service.find_or_create_ingredient(ingredient_data[:ingredient_name], ingredient_data[:quantity], ingredient_data[:unit])
      { ingredient: ingredient, quantity: ingredient_data[:quantity], unit: ingredient_data[:unit] }
    end
  end

  def create_recipe_ingredients(ingredients)
    ingredients.each { |attributes| @recipe.recipe_ingredients.create!(attributes) }
  end

  def update_recipe_ingredients(ingredients)
    @recipe.recipe_ingredients.destroy_all
    create_recipe_ingredients(ingredients)
  end

  def recipe_summaries(recipes)
    ratings = Rating.where(recipe_id: recipes.map(&:id)).group(:recipe_id)
      .pluck(:recipe_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
      .to_h { |recipe_id, average, count| [ recipe_id, [ average, count ] ] }

    recipes.map do |recipe|
      average, count = ratings.fetch(recipe.id, [ nil, 0 ])
      { id: recipe.id, title: recipe.title, average_rating: average.to_f.round(1), total_ratings: count }
    end
  end

  def detailed_recipe_json(recipe)
    nutrition_service = NutritionService.new
    ingredients = recipe.recipe_ingredients.includes(:ingredient).map { |ri| ingredient_details(ri, nutrition_service) }
    nutrition_data = nutrition_service.rounded_nutrition(nutrition_service.sum_nutrition(ingredients))
    {
      id: recipe.id, title: recipe.title, instructions: recipe.instructions,
      user: { id: recipe.user.id },
      ingredients: ingredients,
      ratings: recipe.ratings.map { |rating| { user_id: rating.user_id, rating: rating.rating } },
      average_rating: recipe.ratings.average(:rating).to_f.round(1),
      total_ratings: recipe.ratings.count
    }.merge(nutrition_data)
  end

  def ingredient_details(ri, nutrition_service)
    { ingredient_name: ri.ingredient.ingredient_name, quantity: ri.quantity, unit: ri.unit }
      .merge(nutrition_service.ingredient_nutrition(ri))
  end

  def create_or_update_success_response(message, recipe)
    { status: "success", message: message, data: { recipe: detailed_recipe_json(recipe) } }
  end

  def success_response(message, recipe)
    details = detailed_recipe_json(recipe)
    { status: "success", message: message,
      data: {
        adjusted_recipe: details,
        total_calories: details[:total_calories],
        total_protein: details[:total_protein],
        total_fat: details[:total_fat],
        total_carbs: details[:total_carbs],
        nutrition_available: details[:nutrition_available]
      }
    }
  end
end
