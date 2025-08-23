class AddNameToPantryItems < ActiveRecord::Migration[7.2]
  def change
    add_column :pantry_items, :name, :string
  end
end
