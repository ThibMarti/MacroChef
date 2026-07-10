class RecipeIngredient < ApplicationRecord
  belongs_to :recipe

  before_validation { self.unit = "g" }

  validates :name, presence: true
  validates :quantity, :kcal, :protein_g, :carbs_g, :fat_g,
            numericality: { greater_than_or_equal_to: 0 }
end
