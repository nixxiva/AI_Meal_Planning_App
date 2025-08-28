class Api::V1::RecipesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_recipe, only: [:show, :rate, :adjust, :update, :destroy]
  before_action :check_recipe_ownership, only: [:update, :destroy, :adjust]

  # GET /api/v1/recipes
  def index
    @recipes = @current_user.recipes.includes(:recipe_ingredients, :ingredients, :ratings)

    @recipes = filter_by_ingredient(@recipes) if params[:ingredient].present?
    @recipes = filter_by_search(@recipes) if params[:search].present?

    render json: { data: { recipes: @recipes.map { |recipe| recipe_summary_json(recipe) }, total: @recipes.count }}
  end

  # GET /api/v1/recipes/:id
  def show
    render json: { data: { recipe: detailed_recipe_json(@recipe) }}
  end

  # POST /api/v1/recipes
  def create
    existing_recipe = @current_user.recipes.find_by(title: recipe_params[:title])

    if existing_recipe
      render json: { error: 'A recipe with this title already exists.'}, status: :unprocessable_entity
      return
    end

    @recipe = @current_user.recipes.build(recipe_params)

    if @recipe.save
      create_recipe_ingredients if recipe_ingredients_params.present?

      nutrition_service = NutritionService.new
      nutrition_data = nutrition_service.update_recipe_nutrition(@recipe)

      render json: { message: 'Recipe created successfully', 
        data: {
          recipe: detailed_recipe_json(@recipe), total_calories: nutrition_data[:total_calories],  total_protein: nutrition_data[:total_protein], 
          total_fat: nutrition_data[:total_fat], total_carbs: nutrition_data[:total_carbs]      
        }
      }, status: :created
    else
      render json: { errors: @recipe.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/recipes/:id
  def update
    if @recipe.update(recipe_params)
      update_recipe_ingredients if recipe_ingredients_params.present?
      render json: { message: 'Recipe updated successfully', data: { recipe: detailed_recipe_json(@recipe) }}
    else
      render json: { errors: @recipe.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/recipes/:id
  def destroy
    @recipe.destroy
    render json: { status: 'success', message: 'Recipe deleted successfully' }
  end

  # POST /api/v1/recipes/:id/rate
  def rate
    rating = @recipe.ratings.find_or_initialize_by(user: @current_user)

    if rating.update(rating: rating_params[:rating])
      render json: { status: 'success', message: "Recipe rated successfully", 
        data: { user_rating: rating.rating, average_rating: @recipe.average_rating, total_ratings: @recipe.ratings.count } }
    else
      render json: { status: 'error', errors: rating.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/recipes/:id/adjust
  def adjust
    adjustment_request = {
      recipe_id: @recipe.id,
      current_nutrition: @recipe.nutrition_facts,
      target_calories: params[:target_calories], target_protein: params[:target_protein],
      target_carbs: params[:target_carbs], target_fat: params[:target_fat],
      user_context: Recipe.suitable_for_user_context(@current_user)
    }
    render json: { status: 'success', message: 'Recipe adjustment request created', data: { adjustment_request: adjustment_request, note: 'This request will be processed by your AI service' } }
  end

  private

  def set_recipe
    @recipe = Recipe.find_by(id: params[:id])
    if @recipe.nil?
      render json: { status: 'error', message: "Recipe not found" }, status: :not_found
    end
  end

  def check_recipe_ownership
    unless @recipe.user == @current_user
      render json: { status: 'error', message: "Unauthorized access" }, status: :forbidden
    end
  end

  def recipe_params
    params.require(:recipe).permit(:title, :instructions)
  end

  def recipe_ingredients_params
    params.require(:recipe).permit(recipe_ingredients: [:ingredient_name, :quantity, :unit])[:recipe_ingredients] || []
  end

  def rating_params
    params.require(:rating).permit(:rating)
  end

  def filter_by_ingredient(recipes)
    recipes.joins(:ingredients).where(ingredients: {name: params[:ingredient]})
  end

  def filter_by_search(recipes)
    recipes.where("title ILIKE ?", "%#{params[:search]}%")
  end

  def create_recipe_ingredients
    nutrition_service = NutritionService.new
    
    recipe_ingredients_params.each do |ingredient_data|
      begin
        ingredient = nutrition_service.find_or_create_ingredient(
          ingredient_data[:ingredient_name], ingredient_data[:quantity], ingredient_data[:unit])

        @recipe.recipe_ingredients.create!(ingredient: ingredient, quantity: ingredient_data[:quantity], unit: ingredient_data[:unit])
      rescue => e
        Rails.logger.error "Error creating ingredient: #{e.message}"
      end
    end

    nutrition_service.update_recipe_nutrition(@recipe)
  end

  def update_recipe_ingredients
    @recipe.recipe_ingredients.destroy_all
    create_recipe_ingredients
  end

  def recipe_summary_json(recipe)
    { id: recipe.id, title: recipe.title, average_rating: recipe.ratings.average(:rating).to_f.round(1), total_ratings: recipe.ratings.count }
  end

  def detailed_recipe_json(recipe)

    nutrition_service = NutritionService.new
    {
      id: recipe.id, title: recipe.title, instructions: recipe.instructions,
      user: {
        id: recipe.user.id
      },
      ingredients: recipe.recipe_ingredients.map do |ri|
        ingredient = ri.ingredient
        if ingredient && ingredient.calories_per_gram && ingredient.serving_weight_grams
          total_grams = nutrition_service.get_grams_for_unit(ri.unit) * ri.quantity.to_f
          total_calories = ingredient.calories_per_gram * total_grams
          total_protein = ingredient.protein_per_gram * total_grams
          total_carbs = ingredient.carbs_per_gram * total_grams
          total_fat = ingredient.fat_per_gram * total_grams

          { ingredient_name: ri.ingredient.ingredient_name, quantity: ri.quantity, unit: ri.unit,
            total_calories: total_calories, total_protein: total_protein, total_carbs: total_carbs, total_fat: total_fat }
        else
          { ingredient_name: ri.ingredient.ingredient_name, quantity: ri.quantity, unit: ri.unit,
            total_calories: 0, total_protein: 0, total_carbs: 0, total_fat: 0 }
        end
      end,
      ratings: recipe.ratings.map do |rating|
        { user_id: rating.user_id, rating: rating.rating }
      end,
      average_rating: recipe.ratings.average(:rating).to_f.round(1),
      total_ratings: recipe.ratings.count
    }
  end
end
