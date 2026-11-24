class PantryItem < ApplicationRecord
  belongs_to :user
  belongs_to :ingredient, optional: true

  before_create :ensure_ingredient

  private

  def ensure_ingredient
    service = NutritionService.new
    self.ingredient ||= service.find_or_create_ingredient(self.name, 1, "piece")
  end
end
