class DislikedIngredient < ApplicationRecord
  belongs_to :user

  validates :ingredient_name, uniqueness: { scope: :user_id }
end
