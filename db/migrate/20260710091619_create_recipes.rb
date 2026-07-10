class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.string :name, null: false
      t.string :category, null: false
      t.text :notes

      t.timestamps
    end
    add_index :recipes, :name, unique: true
  end
end
