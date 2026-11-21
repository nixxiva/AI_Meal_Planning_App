require "test_helper"
require Rails.root.join("db/migrate/20261118000000_normalize_meal_plan_recipe_meal_type")

class MealTypeStorageTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "database stores integer meal types and round trips every supported meal" do
    assert_equal :integer, MealPlanRecipe.columns_hash.fetch("meal_type").type
    user = User.new(email: "storage@example.test", password: "password123", first_name: "Storage", last_name: "Test", role: "member")
    user.skip_confirmation!
    user.save!
    plan = user.meal_plans.create!(start_date: Date.current, end_date: Date.current)
    recipe = user.recipes.create!(title: "Storage recipe", instructions: "Cook")
    %w[breakfast lunch dinner].each do |meal_type|
      link = plan.meal_plan_recipes.create!(recipe: recipe, meal_type: meal_type)
      assert_equal meal_type, link.reload.meal_type
    end
  end

  test "forward migration preserves named numeric and null legacy meal types" do
    connection = ActiveRecord::Base.connection
    connection.change_column :meal_plan_recipes, :meal_type, :string
    records = insert_legacy_meals([ "breakfast", "lunch", "dinner", "0", "1", "2", nil ])
    NormalizeMealPlanRecipeMealType.new.migrate(:up)
    assert_equal [ 0, 1, 2, 0, 1, 2, nil ], records.map { |id| connection.select_value("SELECT meal_type FROM meal_plan_recipes WHERE id = #{id}") }
    NormalizeMealPlanRecipeMealType.new.migrate(:up)
    assert_equal :integer, connection.columns(:meal_plan_recipes).find { |column| column.name == "meal_type" }.type
  ensure
    MealPlanRecipe.reset_column_information
  end

  test "forward migration refuses unknown values without changing them" do
    connection = ActiveRecord::Base.connection
    connection.change_column :meal_plan_recipes, :meal_type, :string
    id = insert_legacy_meals([ "snack" ]).first
    assert_raises(ActiveRecord::MigrationError) { NormalizeMealPlanRecipeMealType.new.migrate(:up) }
    assert_equal "snack", connection.select_value("SELECT meal_type FROM meal_plan_recipes WHERE id = #{id}")
    assert_equal :string, connection.columns(:meal_plan_recipes).find { |column| column.name == "meal_type" }.type
  ensure
    MealPlanRecipe.reset_column_information
  end

  private

  def insert_legacy_meals(values)
    user = User.new(email: "legacy@example.test", password: "password123", first_name: "Legacy", last_name: "Test", role: "member")
    user.skip_confirmation!
    user.save!
    plan = user.meal_plans.create!
    recipe = user.recipes.create!(title: "Legacy", instructions: "Cook")
    connection = ActiveRecord::Base.connection
    values.map do |value|
      connection.select_value(<<~SQL)
        INSERT INTO meal_plan_recipes (meal_plan_id, recipe_id, meal_type, created_at, updated_at)
        VALUES (#{plan.id}, #{recipe.id}, #{connection.quote(value)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING id
      SQL
    end
  end
end
