class AddServingWeightAndPerGramNutrientsToIngredients < ActiveRecord::Migration[7.2]
  def change
    add_column :ingredients, :serving_weight_grams, :float
    add_column :ingredients, :calories_per_gram, :float
    add_column :ingredients, :protein_per_gram, :float
    add_column :ingredients, :carbs_per_gram, :float
    add_column :ingredients, :fat_per_gram, :float
  end
end
