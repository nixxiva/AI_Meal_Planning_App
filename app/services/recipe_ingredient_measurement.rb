class RecipeIngredientMeasurement
  REFERENCES = {
    "regular unenriched long-grain white rice cooked without salt" => {
      units: %w[cup cups], unit_grams: 158, source: "USDA SR28 20445",
      reference_grams: 100, totals: { "total_calories" => 130, "total_protein" => 2.69, "total_carbs" => 28.17, "total_fat" => 0.28 }
    },
    "large whole raw egg" => {
      units: %w[egg eggs], unit_grams: 50, source: "USDA SR28 01123",
      reference_grams: 100, totals: { "total_calories" => 143, "total_protein" => 12.56, "total_carbs" => 0.72, "total_fat" => 9.51 }
    },
    "starkist 5 oz chunk light tuna in water drained" => {
      units: %w[can cans], unit_grams: 113, source: "StarKist Chunk Light Tuna in Water 5 oz drained label",
      reference_grams: 113, totals: { "total_calories" => 90, "total_protein" => 20, "total_carbs" => 0, "total_fat" => 0.5 }
    }
  }.freeze

  def self.resolve(normalized_name, quantity, unit, mass_grams_per_unit:)
    reference = REFERENCES[normalized_name]
    return unless reference

    grams_per_unit = mass_grams_per_unit
    grams_per_unit ||= reference.fetch(:unit_grams) if reference.fetch(:units).include?(unit.to_s.strip.downcase)
    amount = Float(quantity, exception: false)
    return unless grams_per_unit && amount&.finite? && amount.positive?

    grams = amount * grams_per_unit
    return unless grams.finite? && grams.positive?

    scale = grams / reference.fetch(:reference_grams)
    totals = reference.fetch(:totals).transform_values { |value| value * scale }
    return unless totals.values.all?(&:finite?)

    { "grams" => grams, "source" => reference.fetch(:source), "totals" => totals }
  end
end
