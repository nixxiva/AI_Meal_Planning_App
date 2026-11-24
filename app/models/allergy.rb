class Allergy < ApplicationRecord
  belongs_to :user

  validates :allergy_name, presence: true, uniqueness: { scope: :user_id }
end
