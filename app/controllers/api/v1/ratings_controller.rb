class Api::V1::RatingsController < ApplicationController
  before_action :authenticate_user!
end
