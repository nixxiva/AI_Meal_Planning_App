require 'httparty'

class Api::V1::PantryItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
	before_action :set_pantry_item, only: [:update, :destroy]

  def index
    @pantry_items = @user.pantry_items.includes(:ingredient)
    render json: @pantry_items.as_json(include: :ingredient)
  end

  def create
    # Getting ingredient name from the request
    ingredient_name = pantry_item_params[:name]

    # Try to find the ingredient in the database by name
    ingredient = Ingredient.find_by(ingredient_name: ingredient_name)

    # Create ingredient if it doesn't exist
    unless ingredient
      nutrition_data = fetch_nutrition_data(ingredient_name)

      if nutrition_data && nutrition_data['foods'].present? && nutrition_data['foods'].first
				food = nutrition_data['foods'].first

				ingredient = Ingredient.create!(
					ingredient_name: ingredient_name,
					unit: food['serving_unit'],
					calories_per_unit: food['nf_calories'],
					protein_per_unit: food['nf_protein'],
					carbs_per_unit: food['nf_total_carbohydrate'],
					fat_per_unit: food['nf_total_fat']
				)

				puts "Ingredient created: #{ingredient.inspect}"
			else
				render json: { error: "Ingredient not found or nutritional data unavailable." }, status: :unprocessable_entity
				return
			end
		end

    # ingredient is either found or created, create pantry_item for user
    pantry_item = @user.pantry_items.new(
			name: ingredient_name,
      quantity: pantry_item_params[:quantity], 
      unit: pantry_item_params[:unit],
      ingredient_id: ingredient.id  # Store ingredient_id as foreign key
    )

    if pantry_item.save
      render json: pantry_item.as_json(include: {ingredient: { only: [:ingredient_name] } }), status: :created
    else
      render json: { error: pantry_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

	def update
		unless @pantry_item
			render json: { error: "Pantry item not found"}, status: :not_found
			return
		end

		update_params = {}

		update_params[:quantity] = pantry_item_params[:quantity] if pantry_item_params[:quantity].present?
		update_params[:unit] = pantry_item_params[:unit] if pantry_item_params[:unit].present?

		if @pantry_item.update(update_params)
			render json: @pantry_item, status: :ok
		else
			render json: { error: @pantry_item.errors.full_messages }, status: :unprocessable_entity
		end
	end

  def destroy
		if @pantry_item.destroy
			render json: { message: "Pantry item deleted successfully"}, status: :ok
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
		unless @pantry_item
			render json: { error: "Pantry item not found for this user."}, status: :not_found
		end
	end

  def pantry_item_params
    params.require(:pantry_item).permit(:name, :quantity, :unit)
  end

  def fetch_nutrition_data(query)
    response = HTTParty.post(
      'https://trackapi.nutritionix.com/v2/natural/nutrients',
      headers: {
        'x-app-id' => '68de7069',
        'x-app-key' => '54b820c1589e40b7b34b22b9e5d4021b',
        'Content-Type' => 'application/json'
      },
      body: { query: query }.to_json
    )

    puts "Nutritionix API Response: #{response.body}"

    response
  end
end
