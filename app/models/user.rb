class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  
  has_many :dietary_preferences, dependent: :destroy
  has_many :allergies, dependent: :destroy
  has_many :disliked_ingredients, dependent: :destroy
  has_many :health_goals, dependent: :destroy
end
