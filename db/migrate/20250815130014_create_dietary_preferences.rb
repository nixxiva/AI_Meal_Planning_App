class CreateDietaryPreferences < ActiveRecord::Migration[7.2]
  def change
    create_table :dietary_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :pref_name

      t.timestamps
    end
  end
end
