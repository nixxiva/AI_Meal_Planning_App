class OpenaiService
  def initialize
    @client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end

  def generate_meal_plan(prompt, require_complete: false)
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "You are a helpful nutritionist." },
          { role: "user", content: prompt }
        ]
      }
    )

    choice = response.dig("choices", 0)
    if require_complete
      raise "OpenAI declined to generate a meal plan" if choice&.dig("message", "refusal").present?
      raise "OpenAI returned an incomplete meal plan" unless choice&.dig("finish_reason") == "stop"
    end

    content = choice&.dig("message", "content")
    raise "OpenAI returned empty response" if content.nil?

    # Remove backticks / markdown and ensure a string
    cleaned = content.gsub(/```json|```/i, "").strip
    cleaned.empty? ? "[]" : cleaned
  rescue Faraday::TooManyRequestsError
    raise "OpenAI rate limit exceeded"
  end
end
