class Api::V1::MealLogsController < ApplicationController
  before_action :authenticate_user!
end
