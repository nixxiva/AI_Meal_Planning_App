class Api::V1::RecipesController < ApplicationController
  before_action :authenticate_user!
end
