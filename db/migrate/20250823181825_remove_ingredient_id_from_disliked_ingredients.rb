class RemoveIngredientIdFromDislikedIngredients < ActiveRecord::Migration[7.2]
  def change
    remove_column :disliked_ingredients, :ingredient_id, :bigint
    add_column :disliked_ingredients, :ingredient_name, :string
  end
end
