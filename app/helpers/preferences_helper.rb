module PreferencesHelper
  # Recipes selectable as a "recurring meal" for a given time of day —
  # breakfast/snack use their own category, lunch/dinner both draw from the
  # "main" catalog (same category mapping as the meal-plan generator).
  def recurring_meal_options(meal_type)
    category = %w[breakfast snack].include?(meal_type) ? meal_type : "main"
    Recipe.where(category: category).order(:name)
  end
end
