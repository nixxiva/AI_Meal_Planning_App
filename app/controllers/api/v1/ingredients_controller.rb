class Api::V1::IngredientsController < ApplicationController
  before_action :authenticate_admin!, only: [ :create, :update, :destroy ]
  before_action :authenticate_user!, only: :search_nutritionix
  before_action :set_ingredient, only: [ :update, :destroy ]

  def index
    render json: Ingredient.order(:ingredient_name, :id).map { |ingredient| ingredient_json(ingredient) }
  end

  def show
    render json: ingredient_json(Ingredient.find(params[:id]))
  end

  def search
    query = params[:query].to_s.strip
    return render(json: { errors: [ "query is required" ] }, status: :bad_request) if query.empty?

    matches = Ingredient.where("ingredient_name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      .order(:ingredient_name, :id)
    render json: matches.map { |ingredient| ingredient_json(ingredient) }
  end

  def search_nutritionix
    query = params[:query].to_s.strip
    quantity = Float(params[:quantity].presence || 1, exception: false)
    unit = params[:unit].presence || "g"
    unless query.present? && query.length <= 200 && quantity&.finite? && quantity.positive? && unit.is_a?(String) && unit.length <= 32
      return render json: { errors: [ "query, positive quantity, and unit are required" ] }, status: :unprocessable_entity
    end

    result = NutritionixService.new.search_nutritionix(query, quantity: quantity, unit: unit)
    if result.is_a?(Hash) && result["foods"].is_a?(Array)
      render json: { foods: result["foods"].map { |food| food.slice("food_name", "serving_qty", "serving_unit", "serving_weight_grams", "nf_calories", "nf_protein", "nf_total_fat", "nf_total_carbohydrate") } }
    else
      render json: { error: "Nutrition lookup unavailable" }, status: :bad_gateway
    end
  end

  def create
    return unless validate_ingredient_numbers

    ingredient = Ingredient.new(ingredient_params)
    if ingredient.save
      render json: ingredient_json(ingredient), status: :created
    else
      render json: { errors: ingredient.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return unless validate_ingredient_numbers

    if @ingredient.update(ingredient_params)
      render json: ingredient_json(@ingredient)
    else
      render json: { errors: @ingredient.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @ingredient.with_lock do
      if @ingredient.pantry_items.exists? || RecipeIngredient.exists?(ingredient_id: @ingredient.id)
        return render json: { error: "Ingredient is used by a pantry item or recipe" }, status: :conflict
      end

      @ingredient.destroy!
    end
    head :no_content
  end

  private

  def set_ingredient
    @ingredient = Ingredient.find(params[:id])
  end

  def ingredient_params
    params.require(:ingredient).permit(:ingredient_name, :calories_per_gram, :protein_per_gram,
      :carbs_per_gram, :fat_per_gram, :serving_weight_grams)
  end

  def ingredient_json(ingredient)
    ingredient.attributes.slice("id", "ingredient_name", "calories_per_gram", "protein_per_gram",
      "carbs_per_gram", "fat_per_gram", "serving_weight_grams")
  end

  def validate_ingredient_numbers
    values = ingredient_params
    values.each do |field, value|
      next unless %w[calories_per_gram protein_per_gram carbs_per_gram fat_per_gram serving_weight_grams].include?(field)
      next if value.nil?

      number = Float(value, exception: false)
      valid = number&.finite? && (field == "serving_weight_grams" ? number.positive? : number >= 0)
      unless valid
        render json: { errors: [ "#{field} must be a finite positive weight or a finite nonnegative value" ] }, status: :unprocessable_entity
        return false
      end
    end
    true
  end
end
