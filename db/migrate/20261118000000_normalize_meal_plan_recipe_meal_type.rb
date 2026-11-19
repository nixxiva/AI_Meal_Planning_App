class NormalizeMealPlanRecipeMealType < ActiveRecord::Migration[7.2]
  def up
    unknown = select_value(<<~SQL)
      SELECT EXISTS (
        SELECT 1 FROM meal_plan_recipes
        WHERE meal_type IS NOT NULL
          AND meal_type::text NOT IN ('0', '1', '2', 'breakfast', 'lunch', 'dinner')
      )
    SQL
    raise ActiveRecord::MigrationError, "Unrecognized meal types require a data decision before conversion" if unknown

    return if connection.columns(:meal_plan_recipes).find { |column| column.name == "meal_type" }.type == :integer

    change_column :meal_plan_recipes, :meal_type, :integer, using: <<~SQL.squish
      CASE meal_type
        WHEN 'breakfast' THEN 0 WHEN 'lunch' THEN 1 WHEN 'dinner' THEN 2
        ELSE meal_type::integer
      END
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Original string representation cannot be recovered"
  end
end
