class AddUniqueIndexToIngredients < ActiveRecord::Migration[7.2]
  def change
    add_index :ingredients, "lower(ingredient_name)", unique: true, name: "index_unique_lowercase_ingredients"
  end
end
