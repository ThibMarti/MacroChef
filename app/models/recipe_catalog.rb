# Query interface onto the Recipe table, grouped by category. Used by
# PreferencesController (constrains the initial meal-plan generation) and
# SearchRecipesTool (lets the LLM look up catalog dishes during follow-up
# chat). Recipes are the single source of truth — editing a recipe's
# ingredients/macros in the Recipes UI changes what future meal plans use.
module RecipeCatalog
  # `recipe_ids`, when given, restricts the catalog to just those recipes
  # (e.g. a user's favorites) — used by PreferencesController when the
  # calculator's "only use my favorites" option is checked. If a category
  # would end up with zero options under that restriction (e.g. no
  # favorited snacks), catalog_for falls back to the full unfiltered
  # category so plan generation never has an empty catalog to pick from.
  def self.recipes(recipe_ids: nil)
    catalog_for("main", recipe_ids)
  end

  def self.breakfast_options(recipe_ids: nil)
    catalog_for("breakfast", recipe_ids)
  end

  def self.snack_options(recipe_ids: nil)
    catalog_for("snack", recipe_ids)
  end

  def self.index
    (recipes + breakfast_options + snack_options).each_with_object({}) do |dish, idx|
      idx[dish[:name]] = dish
    end
  end

  def self.for_meal_type(meal_type)
    case meal_type.to_s.downcase
    when "breakfast" then breakfast_options
    when "snack" then snack_options
    when "lunch", "dinner" then recipes
    else recipes + breakfast_options + snack_options
    end
  end

  def self.catalog_for(category, recipe_ids = nil)
    scope = Recipe.where(category: category)
    scope = scope.where(id: recipe_ids) if recipe_ids.present?

    result = scope.order(:name).map(&:as_catalog_hash)
    return result if result.present? || recipe_ids.blank?

    # Fallback: the restriction left this category empty — use the full
    # category instead of generating with no options at all.
    Recipe.where(category: category).order(:name).map(&:as_catalog_hash)
  end
end
