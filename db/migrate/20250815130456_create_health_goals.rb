class CreateHealthGoals < ActiveRecord::Migration[7.2]
  def change
    create_table :health_goals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :goal_name

      t.timestamps
    end
  end
end
