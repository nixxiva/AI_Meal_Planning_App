class Allergy < ApplicationRecord
  belongs_to :user

  validates :allergy_name, uniqueness: { scope: :user_id }

end
