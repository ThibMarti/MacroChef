class Recipe < ApplicationRecord
  CATEGORIES = %w[main breakfast snack].freeze

  has_many :recipe_ingredients, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_one_attached :photo

  accepts_nested_attributes_for :recipe_ingredients,
                                 allow_destroy: true,
                                 reject_if: proc { |attrs| attrs["name"].blank? }

  validates :name, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }

  scope :ordered, -> { order(:category, :name) }

  # Ruby-level sum (not `.sum(:kcal)`, a separate SQL aggregate query each
  # time) — this loads recipe_ingredients ONCE and reuses that loaded array
  # for all four totals, instead of 4 round-trips per recipe. Matters a lot
  # here: these are called for every recipe in the catalog, for every meal,
  # for every day of a plan.
  def total_kcal      = recipe_ingredients.sum(&:kcal)
  def total_protein_g = recipe_ingredients.sum(&:protein_g)
  def total_carbs_g   = recipe_ingredients.sum(&:carbs_g)
  def total_fat_g     = recipe_ingredients.sum(&:fat_g)

  # Shape consumed by RecipeCatalog / SearchRecipesTool / the meal-plan
  # generator — kept identical to the old hardcoded-array format so nothing
  # downstream needs to change when recipes move from Ruby constants to DB.
  def as_catalog_hash
    {
      name: name,
      kcal: total_kcal,
      protein_g: total_protein_g,
      carbs_g: total_carbs_g,
      fat_g: total_fat_g
    }
  end

  def favorited_by?(user)
    return false unless user

    favorites.exists?(user: user)
  end
end
