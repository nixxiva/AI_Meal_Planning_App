class RemoveNutrionFromRecipes < ActiveRecord::Migration[7.2]
  def change
    remove_column :recipes, :calories, :string
    remove_column :recipes, :protein, :string
    remove_column :recipes, :carbs, :string
    remove_column :recipes, :fat, :string

    change_column :recipes, :instructions, :text
  end
end
