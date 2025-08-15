class CreateDislikedIngredients < ActiveRecord::Migration[7.2]
  def change
    create_table :disliked_ingredients do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ingredient_name

      t.timestamps
    end
  end
end
