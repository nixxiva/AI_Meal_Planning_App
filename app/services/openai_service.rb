class OpenaiService
  def initialize
    @client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end

  def generate_meal_plan(prompt)
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "You are a helpful nutritionist." },
          { role: "user", content: prompt }
        ]
      }
    )

    content = response.dig("choices", 0, "message", "content")
    raise "OpenAI returned empty response" if content.nil?

    # Remove backticks / markdown and ensure a string
    cleaned = content.gsub(/```json|```/i, '').strip
    cleaned.empty? ? "[]" : cleaned
  rescue Faraday::TooManyRequestsError
    raise "OpenAI rate limit exceeded"
  end
end
