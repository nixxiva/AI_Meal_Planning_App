class HealthGoal < ApplicationRecord
  has_many :user

  validates :goal_name, presence: true
end
