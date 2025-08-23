class CreatePantryItems < ActiveRecord::Migration[7.2]
  def change
    create_table :pantry_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :ingredient, null: false, foreign_key: true
      t.float :quantity
      t.string :unit

      t.timestamps
    end
  end
end
