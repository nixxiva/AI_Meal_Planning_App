class Api::V1::PantryItemsController < ApplicationController
  DECIMAL_QUANTITY = /\A *[+-]?(?<significand>[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)? *\z/

  before_action :authenticate_user!
  before_action :set_user
  before_action :set_pantry_item, only: [ :update, :destroy ]
  before_action :set_pantry_item_attributes, only: [ :create, :update ]

  # GET /api/v1/users/:user_id/pantry_items
  def index
    @pantry_items = @user.pantry_items.includes(:ingredient)
    render json: @pantry_items.as_json(include: :ingredient)
  end

  # POST /api/v1/users/:user_id/pantry_items
  def create
    ingredient = NutritionService.new.find_or_create_ingredient(
      @pantry_item_attributes[:name],
      @pantry_item_attributes[:quantity],
      @pantry_item_attributes[:unit]
    )

    # if no ingredient in database
    unless ingredient
      render json: { error: "Ingredient not found or nutritional data unavailable." }, status: :unprocessable_entity
      return
    end

    pantry_item = @user.pantry_items.new(@pantry_item_attributes.merge(ingredient_id: ingredient.id))

    if pantry_item.save
      render json: pantry_item.as_json(include: { ingredient: { only: [ :ingredient_name ] } }), status: :created
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

    update_attributes = @pantry_item_attributes.compact

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

  def set_pantry_item
    @pantry_item = @user.pantry_items.find_by(id: params[:id])
    render json: { error: "Pantry item not found for this user." }, status: :not_found unless @pantry_item
  end

  def set_pantry_item_attributes
    submitted = params.require(:pantry_item)
    raw_quantity = submitted[:quantity]
    unless raw_quantity.nil?
      quantity = parse_quantity(quantity_input(raw_quantity))
      if quantity.nil?
        return render json: { error: "Quantity must be a finite, nonnegative number." }, status: :unprocessable_entity
      end
    end

    @pantry_item_attributes = submitted.permit(:name, :quantity, :unit)
    @pantry_item_attributes[:quantity] = quantity unless raw_quantity.nil?
  end

  def quantity_input(value)
    return value unless value.is_a?(Float) && value.zero? && request.content_mime_type&.symbol == :json
    return value if request.query_parameters.key?("pantry_item") || request.path_parameters.key?(:pantry_item)

    # A tiny JSON number can round to zero before Rails passes it to the controller.
    body = JSON.parse(request.raw_post, decimal_class: String)
    return unless body.is_a?(Hash)

    item = body.fetch("pantry_item", body)
    item["quantity"] if item.is_a?(Hash)
  end

  def parse_quantity(value)
    string_quantity = value.is_a?(String)
    return unless string_quantity || value.is_a?(Numeric)

    if string_quantity
      decimal = DECIMAL_QUANTITY.match(value)
      return unless decimal
      return 0.0 unless decimal[:significand].match?(/[1-9]/)
    end

    quantity = Float(value, exception: false)
    return unless quantity&.finite? && quantity >= 0
    return if string_quantity && quantity.zero?

    quantity
  end
end
