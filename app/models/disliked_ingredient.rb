class DislikedIngredient < ApplicationRecord
  belongs_to :user

  validates :ingredient_name, presence: true, uniqueness: { scope: :user_id }
end
