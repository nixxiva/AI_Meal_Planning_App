class MealPlanRecipe < ApplicationRecord
  belongs_to :meal_plan
  belongs_to :recipe

  enum meal_type: { breakfast: 0, lunch: 1, dinner: 2 }
end
