class CreateRecipes < ActiveRecord::Migration[7.2]
  def change
    create_table :recipes do |t|
      t.string :title
      t.string :instructions
      t.float :calories
      t.float :protein
      t.float :carbs
      t.float :fat
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
