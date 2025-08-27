class AddMealTypeToMealPlanRecipes < ActiveRecord::Migration[7.2]
  def change
    add_column :meal_plan_recipes, :meal_type, :string
  end
end
