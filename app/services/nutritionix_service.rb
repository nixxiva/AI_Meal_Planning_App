require "httparty"

class NutritionixService
  BASE_URL = "https://trackapi.nutritionix.com/v2"

  def initialize
    @headers = {
      "x-app-id" => ENV["NUTRITIONIX_APP_ID"],
      "x-app-key" => ENV["NUTRITIONIX_APP_KEY"],
      "Content-Type" => "application/json"
    }
  end
end
