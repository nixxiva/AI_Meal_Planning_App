class Recipe < ApplicationRecord
  belongs_to :user

  has_many :ratings, dependent: :destroy

  has_many :recipe_ingredients, dependent: :destroy

  accepts_nested_attributes_for :recipe_ingredients

  has_many :ingredients, through: :recipe_ingredients
end
