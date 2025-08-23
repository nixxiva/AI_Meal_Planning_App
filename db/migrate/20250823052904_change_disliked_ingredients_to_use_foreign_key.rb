class ChangeDislikedIngredientsToUseForeignKey < ActiveRecord::Migration[7.2]
  def change
    add_reference :disliked_ingredients, :ingredient, foreign_key: true

    remove_column :disliked_ingredients, :ingredient_name, :string
  end
end
