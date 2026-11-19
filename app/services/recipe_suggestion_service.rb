class RecipeSuggestionService
  def suggest_substitute(missing_ingredient, allergies:, disliked_ingredients:, dietary_preferences:)
    prompt = <<~PROMPT
      Suggest one practical substitute for the ingredient "#{missing_ingredient}" 
      that can be used in everyday cooking.
      Allergies: #{allergies.join(", ")}
      Disliked ingredients: #{disliked_ingredients.join(", ")}
      Dietary preferences: #{dietary_preferences.join(", ")}
      Respect these restrictions. Respond only with the substitute name, or an empty response if unavailable.
    PROMPT

    response = OpenaiService.new.generate_meal_plan(prompt)

    return nil unless response.is_a?(String) && response.strip.present?

    suggestion = response.strip
    return nil if suggestion == "[]"

    excluded = (allergies + disliked_ingredients).map { |name| name.to_s.strip.downcase }
    excluded.include?(suggestion.downcase) ? nil : suggestion
  rescue => e
    Rails.logger.error("Substitute suggestion failed: #{e.message}")
    nil
  end
end
