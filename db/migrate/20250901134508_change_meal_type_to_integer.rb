class ChangeMealTypeToInteger < ActiveRecord::Migration[7.2]
  def change
    change_column :meal_plan_recipes, :meal_type, :integer, using: 'meal_type::integer'
  end
end
