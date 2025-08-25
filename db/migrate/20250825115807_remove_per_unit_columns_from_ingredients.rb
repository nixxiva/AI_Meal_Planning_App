class RemovePerUnitColumnsFromIngredients < ActiveRecord::Migration[7.2]
  def change
    remove_column :ingredients, :calories_per_unit, :float
    remove_column :ingredients, :protein_per_unit, :float
    remove_column :ingredients, :carbs_per_unit, :float
    remove_column :ingredients, :fat_per_unit, :float
  end
end
