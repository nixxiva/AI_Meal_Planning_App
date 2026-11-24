class AddNutritionMeasureToRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipe_ingredients, :nutrition_measure, :jsonb
  end
end
