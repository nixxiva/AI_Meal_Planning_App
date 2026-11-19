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

  def search_nutritionix(query, quantity: 1, unit: "g")
    response = HTTParty.post(
      "#{BASE_URL}/natural/nutrients",
      headers: @headers,
      body: { query: "#{quantity} #{unit} of #{query}" }.to_json
    )
    response.success? ? response.parsed_response : nil
  rescue StandardError => error
    Rails.logger.error("Nutritionix search failed: #{error.message}")
    nil
  end
end
