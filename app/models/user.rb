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
  has_many :health_goals, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, :role, presence: true
end
