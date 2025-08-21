class RemoveUserIdFromHealthGoals < ActiveRecord::Migration[7.2]
  def change
    remove_column :health_goals, :user_id, :integer
  end
end
