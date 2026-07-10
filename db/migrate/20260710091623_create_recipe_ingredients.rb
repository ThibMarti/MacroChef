class CreateRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :quantity, precision: 8, scale: 2, null: false, default: 1
      t.string :unit, null: false, default: "serving"
      t.decimal :kcal, precision: 8, scale: 2, null: false, default: 0
      t.decimal :protein_g, precision: 8, scale: 2, null: false, default: 0
      t.decimal :carbs_g, precision: 8, scale: 2, null: false, default: 0
      t.decimal :fat_g, precision: 8, scale: 2, null: false, default: 0

      t.timestamps
    end
  end
end
