require 'json'

# Simulation
class OpenaiService
  def generate_meal_plan_mock(preferences)
    response_content = <<~JSON
      ```json
      [
        {
          "title": "Oatmeal with Berries",
          "ingredients": ["oats", "milk", "blueberries", "honey"],
          "instructions": "Cook oats with milk, top with berries and honey.",
          "meal_type": "breakfast"
        },
        {
          "title": "Grilled Chicken Salad",
          "ingredients": ["chicken breast", "lettuce", "tomatoes", "olive oil"],
          "instructions": "Grill chicken, toss with salad ingredients.",
          "meal_type": "lunch"
        }
      ]
      ```
    JSON

    # PARSE
    json_string = response_content.gsub(/```json|```/, '').strip
    JSON.parse(json_string)
  end
end

service = OpenaiService.new
preferences = { dietary_preferences: [], allergies: [], health_goals: ["weight loss"] }
meal_plan = service.generate_meal_plan_mock(preferences)
puts meal_plan
