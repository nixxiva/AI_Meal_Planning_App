class CreateAllergies < ActiveRecord::Migration[7.2]
  def change
    create_table :allergies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :allergy_name

      t.timestamps
    end
  end
end
