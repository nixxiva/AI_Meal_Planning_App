class HealthGoal < ApplicationRecord
  has_many :users

  validates :goal_name, presence: true
end
