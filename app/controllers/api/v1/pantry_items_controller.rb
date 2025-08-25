class Api::V1::PantryItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :set_pantry_item, only: [:update, :destroy]

  def index
    @pantry_items = @user.pantry_items.includes(:ingredient)
    render json: @pantry_items.as_json(include: :ingredient)
  end

 def create
  ingredient = find_or_create_ingredient(
    pantry_item_params[:name],
    pantry_item_params[:quantity],
    pantry_item_params[:unit]
  )

  if ingredient.nil?
    render json: { error: "Ingredient not found or nutritional data unavailable." }, status: :unprocessable_entity
    return
  end

  pantry_item = @user.pantry_items.new(
    name: pantry_item_params[:name],
    quantity: pantry_item_params[:quantity],
    unit: pantry_item_params[:unit],
    ingredient_id: ingredient.id
  )

  if pantry_item.save
    render json: pantry_item.as_json(include: { ingredient: { only: [:ingredient_name] } }), status: :created
  else
    render json: { error: pantry_item.errors.full_messages }, status: :unprocessable_entity
  end
end

  def update
    unless @pantry_item
      render json: { error: "Pantry item not found" }, status: :not_found
      return
    end

    update_attributes = pantry_item_params.compact
    
    if update_attributes[:name].present? && update_attributes[:name] != @pantry_item.name
      new_ingredient = find_or_create_ingredient(
        update_attributes[:name],
        update_attributes[:quantity] || @pantry_item.quantity,
        update_attributes[:unit] || @pantry_item.unit
      )
      
      if new_ingredient.nil?
        render json: { error: "New ingredient not found or nutritional data unavailable." }, status: :unprocessable_entity
        return
      end
      
      update_attributes[:ingredient_id] = new_ingredient.id
    end
    
    if @pantry_item.update(update_attributes)
      render json: @pantry_item, status: :ok
    else
      render json: { error: @pantry_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @pantry_item.destroy
      render json: { message: "Pantry item deleted successfully" }, status: :ok
    else
      render json: { error: @pantry_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_pantry_item
    @pantry_item = @user.pantry_items.find_by(id: params[:id])
    render json: { error: "Pantry item not found for this user." }, status: :not_found unless @pantry_item
  end

  def pantry_item_params
    params.require(:pantry_item).permit(:name, :quantity, :unit)
  end

  def find_or_create_ingredient(ingredient_name, quantity, unit)
    ingredient = Ingredient.find_by(ingredient_name: ingredient_name)

    unless ingredient
      nutrition_data = fetch_nutrition_data(ingredient_name, quantity, unit)

      if nutrition_data && nutrition_data['foods'].present?
        food = nutrition_data['foods'].first
        
        total_grams = food['serving_weight_grams']
        if total_grams.nil? || total_grams.zero?
          return nil 
        end

        grams_per_serving_unit = total_grams / food['serving_qty']
        
        calories_per_gram = food['nf_calories'] / total_grams
        protein_per_gram = food['nf_protein'] / total_grams
        carbs_per_gram = food['nf_total_carbohydrate'] / total_grams
        fat_per_gram = food['nf_total_fat'] / total_grams

        ingredient = Ingredient.create(
          ingredient_name: ingredient_name,
          calories_per_gram: calories_per_gram,
          protein_per_gram: protein_per_gram,
          carbs_per_gram: carbs_per_gram,
          fat_per_gram: fat_per_gram,
          serving_weight_grams: grams_per_serving_unit
        )
      end
    end

    ingredient
  end

  def fetch_nutrition_data(query, quantity, unit)
  begin
    nutritionix_credentials = Rails.application.credentials.nutritionix

    formatted_query = "#{quantity} #{unit} of #{query}"

    response = HTTParty.post(
      'https://trackapi.nutritionix.com/v2/natural/nutrients',
      headers: {
        'x-app-id' => nutritionix_credentials[:app_id],
        'x-app-key' => nutritionix_credentials[:app_key],
        'Content-Type' => 'application/json'
      },
      body: { query: formatted_query }.to_json
    )
    response.parsed_response
  rescue StandardError => e
    Rails.logger.error "Error fetching data from Nutritionix API: #{e.message}"
    nil
  end
end
end