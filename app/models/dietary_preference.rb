class DietaryPreference < ApplicationRecord
  belongs_to :user

  validates :pref_name, presence: true, uniqueness: { scope: :user_id }

end
