# Computes authoritative macros for a meal plan's meals, always deriving
# numbers from RecipeCatalog (the DB) rather than trusting LLM arithmetic or
# user-picked values. Shared by PreferencesController (initial plan
# generation) and MessagesController#swap_meal (replacing one dish in an
# existing plan) so both paths stay consistent.
module MealPlanMacros
  # Rough share of the day's calories each meal_type should get, used to
  # split target_kcal across a day's meals. Normalized per-day against
  # whichever meal_types actually appear, so this doesn't need to sum to 1
  # and doesn't need every meal_type listed.
  MEAL_TYPE_WEIGHT = {
    "breakfast" => 0.25,
    "lunch" => 0.35,
    "dinner" => 0.30,
    "snack" => 0.10
  }.freeze
  DEFAULT_MEAL_TYPE_WEIGHT = 0.20

  def self.allocate_day!(meals, target_kcal)
    weights = meals.map { |meal| MEAL_TYPE_WEIGHT.fetch(meal["meal_type"], DEFAULT_MEAL_TYPE_WEIGHT) }
    total_weight = weights.sum
    return if total_weight <= 0

    meals.each_with_index do |meal, index|
      share_kcal = target_kcal * (weights[index] / total_weight)
      recompute_meal!(meal, share_kcal)
    end
  end

  # Recomputes a single meal's macros from RecipeCatalog, scaling the dish's
  # base (one-serving) macros so its kcal lands on share_kcal, then rescales
  # the meal's ingredient list proportionally to match. Mutates `meal` and
  # returns it; no-ops if the dish name isn't in the catalog.
  def self.recompute_meal!(meal, share_kcal)
    base = RecipeCatalog.index[meal["name"]]
    return meal unless base

    # RecipeCatalog values come from the DB as BigDecimal — coerce to Float
    # so JSON.generate emits plain numbers instead of quoted decimal strings.
    base_kcal = base[:kcal].to_f
    scale = base_kcal.zero? ? 1.0 : share_kcal / base_kcal

    corrected = {
      "serving_scale" => scale.round(2),
      "kcal" => (base_kcal * scale).round,
      "protein_g" => (base[:protein_g].to_f * scale).round(1),
      "carbs_g" => (base[:carbs_g].to_f * scale).round(1),
      "fat_g" => (base[:fat_g].to_f * scale).round(1)
    }

    rescale_ingredients!(meal["ingredients"], corrected["kcal"])
    meal.merge!(corrected)
  end

  # Builds a fresh ingredients array for `meal` from a Recipe's own
  # (structured, user-editable) ingredient list, scaled so the meal's total
  # kcal lands on share_kcal. Used when swapping a meal for a specific
  # Recipe record (as opposed to recompute_meal!, which works from the
  # LLM's invented ingredient list and a catalog name).
  def self.apply_recipe!(meal, recipe, share_kcal)
    base_kcal = recipe.total_kcal.to_f
    scale = base_kcal.zero? ? 1.0 : share_kcal / base_kcal

    meal["name"] = recipe.name
    meal["serving_scale"] = scale.round(2)
    meal["kcal"] = base_kcal.zero? ? 0 : (base_kcal * scale).round
    meal["protein_g"] = (recipe.total_protein_g.to_f * scale).round(1)
    meal["carbs_g"] = (recipe.total_carbs_g.to_f * scale).round(1)
    meal["fat_g"] = (recipe.total_fat_g.to_f * scale).round(1)
    meal["ingredients"] = recipe.recipe_ingredients.map do |ingredient|
      {
        "name" => ingredient.name,
        "quantity" => (ingredient.quantity.to_f * scale).round,
        "unit" => ingredient.unit,
        "kcal" => (ingredient.kcal.to_f * scale).round,
        "protein_g" => (ingredient.protein_g.to_f * scale).round(1),
        "carbs_g" => (ingredient.carbs_g.to_f * scale).round(1),
        "fat_g" => (ingredient.fat_g.to_f * scale).round(1)
      }
    end
    meal["steps"] = []
    meal
  end

  # Returns DISPLAY macros for `meal`, recomputed live from the current
  # Recipe (by name): each ingredient keeps whatever quantity is stored on
  # THIS meal instance (editable per plan/day via MessagesController#update_ingredient),
  # but its kcal/protein_g/carbs_g/fat_g are re-derived from the recipe's
  # CURRENT per-gram rate for that ingredient. So editing a recipe's macros
  # updates every plan that uses it, and editing one meal's portion size
  # (grams) only affects that meal — both stay live. The stored JSON is never
  # touched here, only the returned hash used for rendering. Ingredients (or
  # whole meals) that no longer match a recipe/ingredient by name fall back
  # to their stored values.
  def self.live_macros(meal)
    recipe = Recipe.find_by(name: meal["name"])
    return meal unless recipe

    recipe_ingredients_by_name = recipe.recipe_ingredients.index_by(&:name)

    ingredients = Array(meal["ingredients"]).map do |ingredient|
      rate_for(recipe_ingredients_by_name[ingredient["name"]], ingredient)
    end

    meal.merge(
      "kcal" => ingredients.sum { |i| i["kcal"].to_f }.round,
      "protein_g" => ingredients.sum { |i| i["protein_g"].to_f }.round(1),
      "carbs_g" => ingredients.sum { |i| i["carbs_g"].to_f }.round(1),
      "fat_g" => ingredients.sum { |i| i["fat_g"].to_f }.round(1),
      "ingredients" => ingredients
    )
  end

  def self.rate_for(recipe_ingredient, stored_ingredient)
    return stored_ingredient unless recipe_ingredient && recipe_ingredient.quantity.to_f.positive?

    per_gram = per_gram_rate(recipe_ingredient)
    quantity = stored_ingredient["quantity"].to_f
    apply_rate(stored_ingredient, per_gram, quantity)
  end
  private_class_method :rate_for

  # Changes one ingredient's quantity to `new_quantity` and recomputes its
  # macros to match, persisting the result (unlike live_macros, which only
  # computes DISPLAY values without saving). Prefers the matching Recipe
  # ingredient's current per-gram rate (so it stays in sync with future
  # recipe edits); falls back to the ingredient's OWN pre-edit rate — derived
  # from its stored kcal/protein/carbs/fat at its OLD quantity, before we
  # overwrite anything — when no recipe ingredient matches by name (e.g. an
  # older plan whose ingredient names don't exactly match the recipe, like
  # "Beef" vs "Ground Beef"). Without this fallback, editing the quantity of
  # such an ingredient would silently do nothing to its macros.
  def self.set_ingredient_quantity!(ingredient, recipe, new_quantity)
    recipe_ingredient = recipe&.recipe_ingredients&.find_by(name: ingredient["name"])

    per_gram = if recipe_ingredient && recipe_ingredient.quantity.to_f.positive?
                 per_gram_rate(recipe_ingredient)
               elsif ingredient["quantity"].to_f.positive?
                 per_gram_rate(ingredient)
               end

    if per_gram
      ingredient.merge!(apply_rate(ingredient, per_gram, new_quantity))
    else
      ingredient["quantity"] = new_quantity.round
    end

    ingredient
  end

  # `source` is either a RecipeIngredient (recipe's canonical ingredient) or
  # a plain Hash (a meal's own stored ingredient, with string keys).
  def self.per_gram_rate(source)
    if source.is_a?(Hash)
      quantity, kcal, protein_g, carbs_g, fat_g =
        source.values_at("quantity", "kcal", "protein_g", "carbs_g", "fat_g")
    else
      quantity, kcal, protein_g, carbs_g, fat_g =
        [source.quantity, source.kcal, source.protein_g, source.carbs_g, source.fat_g]
    end

    quantity = quantity.to_f

    {
      kcal: kcal.to_f / quantity,
      protein_g: protein_g.to_f / quantity,
      carbs_g: carbs_g.to_f / quantity,
      fat_g: fat_g.to_f / quantity
    }
  end
  private_class_method :per_gram_rate

  def self.apply_rate(stored_ingredient, per_gram, quantity)
    stored_ingredient.merge(
      "quantity" => quantity.round,
      "unit" => "g",
      "kcal" => (per_gram[:kcal] * quantity).round,
      "protein_g" => (per_gram[:protein_g] * quantity).round(1),
      "carbs_g" => (per_gram[:carbs_g] * quantity).round(1),
      "fat_g" => (per_gram[:fat_g] * quantity).round(1)
    )
  end
  private_class_method :apply_rate

  # Proportionally rescales an ingredient list so its macros sum to the
  # authoritative meal kcal, preserving relative proportions between
  # ingredients while making the displayed totals exact.
  def self.rescale_ingredients!(ingredients, target_kcal)
    return if ingredients.blank?

    naive_total = ingredients.sum { |ingredient| ingredient["kcal"].to_f }
    return if naive_total <= 0

    factor = target_kcal / naive_total

    ingredients.each do |ingredient|
      ingredient["quantity"] = (ingredient["quantity"].to_f * factor).round
      ingredient["kcal"] = (ingredient["kcal"].to_f * factor).round
      ingredient["protein_g"] = (ingredient["protein_g"].to_f * factor).round(1)
      ingredient["carbs_g"] = (ingredient["carbs_g"].to_f * factor).round(1)
      ingredient["fat_g"] = (ingredient["fat_g"].to_f * factor).round(1)
    end
  end
end
