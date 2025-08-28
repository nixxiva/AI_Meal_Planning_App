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

  def search_food(query)
    url = "#{BASE_URL}/natural/nutrients"
    body = { query: query }.to_json

    response = HTTParty.post(url, headers: @headers, body: body)
    return {} unless response.code == 200

    data = JSON.parse(response.body)
    food = data["foods"]&.first || {}
    {
      "serving_weight_grams" => food["serving_weight_grams"] || 0,
      "calories_per_gram" => food["nf_calories"].to_f / (food["serving_weight_grams"] || 1),
      "protein_per_gram" => food["nf_protein"].to_f / (food["serving_weight_grams"] || 1),
      "carbs_per_gram" => food["nf_total_carbohydrate"].to_f / (food["serving_weight_grams"] || 1),
      "fat_per_gram" => food["nf_total_fat"].to_f / (food["serving_weight_grams"] || 1)
    }
    rescue JSON::ParserError
    {}
  end
end
