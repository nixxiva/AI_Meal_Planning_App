class AddHealthGoalToUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :users, :health_goal, null: true, foreign_key: true
  end
end
