class CreateIngredients < ActiveRecord::Migration[7.2]
  def change
    create_table :ingredients do |t|
      t.string :ingredient_name
      t.string :unit
      t.float :calories_per_unit
      t.float :protein_per_unit
      t.float :carbs_per_unit
      t.float :fat_per_unit

      t.timestamps
    end
  end
end
