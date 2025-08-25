class User < ApplicationRecord

  include Devise::JWT::RevocationStrategies::JTIMatcher
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
        :recoverable, :rememberable, :validatable, :confirmable,
        :jwt_authenticatable, jwt_revocation_strategy: self
  
  has_many :dietary_preferences, dependent: :destroy
  has_many :allergies, dependent: :destroy
  has_many :disliked_ingredients, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :ratings, dependent: :destroy
  has_many :meal_logs, dependent: :destroy
  has_many :pantry_items, dependent: :destroy
  belongs_to :health_goal, optional: true

  # use nested attributes in controller and for destroy attributee
  accepts_nested_attributes_for :allergies, allow_destroy: true
  accepts_nested_attributes_for :disliked_ingredients, allow_destroy: true
  accepts_nested_attributes_for :dietary_preferences, allow_destroy: true

  # one or more rule

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, :role, presence: true

  private

  def has_at_least_one_dietary_preference
    if @user.confirmed? && dietary_preferences.empty?
      errors.add(:base, "User must select at least one dietary preference")
    end
  end
end
