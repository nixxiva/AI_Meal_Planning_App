class MealPlan < ApplicationRecord
  belongs_to :user
  has_many :meal_plan_recipes, dependent: :destroy
  has_many :recipes, through: :meal_plan_recipes
  
  # validates :start_date, :end_date, presence: true
end
