class CreateMealLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :meal_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.float :quantity
      t.date :date

      t.timestamps
    end
  end
end
