class Api::V1::MealPlansController < ApplicationController
  before_action :authenticate_user!
end
