module Api
  module V1
    class HealthGoalsController < ApplicationController
			def index
				render json: HealthGoal.all
			end
    end
  end
end
