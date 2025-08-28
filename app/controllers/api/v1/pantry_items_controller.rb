class Api::V1::PantryItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :set_pantry_item, only: [:update, :destroy]

  # GET /api/v1/users/:user_id/pantry_items
  def index
    @pantry_items = @user.pantry_items.includes(:ingredient)
    render json: @pantry_items.as_json(include: :ingredient)
  end

  # POST /api/v1/users/:user_id/pantry_items
  def create
    ingredient = NutritionService.new.find_or_create_ingredient(
      pantry_item_params[:name],
      pantry_item_params[:quantity],
      pantry_item_params[:unit]
    )

    # if no ingredient in database
    unless ingredient
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

  # PATCH/PUT /api/v1/users/:user_id/pantry_items/:id
  # Updates an existing pantry item. If the name is changed, a new ingredient
  def update
    unless @pantry_item
      render json: { error: "Pantry item not found" }, status: :not_found
      return
    end

    update_attributes = pantry_item_params.compact
    
    # Check if the ingredient name is being updated.
    if update_attributes[:name].present? && update_attributes[:name] != @pantry_item.name
      new_ingredient = NutritionService.new.find_or_create_ingredient(
        update_attributes[:name],
        # Use existing quantity and unit if not provided in the update.
        update_attributes[:quantity] || @pantry_item.quantity,
        update_attributes[:unit] || @pantry_item.unit
      )
      
      unless new_ingredient
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

  # DELETE /api/v1/users/:user_id/pantry_items/:id
  # Deletes a pantry item.
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
end