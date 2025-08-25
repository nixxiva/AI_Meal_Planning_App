class RemoveUnitFromIngredients < ActiveRecord::Migration[7.2]
  def change
    remove_column :ingredients, :unit, :string
  end
end
