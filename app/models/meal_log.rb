class MealLog < ApplicationRecord
  belongs_to :user
  belongs_to :recipe

  validates :quantity, numericality: { greater_than: 0, less_than: Float::INFINITY }
end
