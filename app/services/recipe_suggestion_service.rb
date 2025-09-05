class RecipeSuggestionService
  def suggest_substitute(missing_ingredient)
    prompt = <<~PROMPT
      Suggest one practical substitute for the ingredient "#{missing_ingredient}" 
      that can be used in everyday cooking. Respond only with the substitute name.
    PROMPT

    response = OpenaiService.new.generate_meal_plan(prompt)

    if response.is_a?(String)
      response.strip
    else
      nil
    end
  rescue => e
    Rails.logger.error("Substitute suggestion failed: #{e.message}")
    nil
  end
end
