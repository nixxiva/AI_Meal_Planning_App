class DietaryPreference < ApplicationRecord
  belongs_to :user

  validates :pref_name, uniqueness: { scope: :user_id }

end
