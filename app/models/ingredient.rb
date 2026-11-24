class Ingredient < ApplicationRecord
  has_many :pantry_items
  validates :ingredient_name, presence: true, uniqueness: { case_sensitive: false }

  before_save :normalize_name

  private

  def normalize_name
    self.ingredient_name = ingredient_name.strip.downcase
  end
end
