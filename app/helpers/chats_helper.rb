module ChatsHelper
  # Tries to parse an assistant message as a MacroChef meal-plan JSON payload
  # (the format defined by PreferencesController#system_prompt). Returns the
  # parsed Hash, or nil if the message isn't valid JSON in that shape — so the
  # view can fall back to plain text rendering for anything else.
  def meal_plan_payload(message)
    return nil unless message.role == "assistant"

    parsed = JSON.parse(message.content)
    parsed if parsed.is_a?(Hash) && parsed["week"].present?
  rescue JSON::ParserError
    nil
  end

  # Finds the profile (target_kcal, diet_type, goal, ...) for a chat's meal
  # plan, used for summary cards where the full week isn't shown. Returns nil
  # if the chat has no assistant message with a valid plan yet.
  def meal_plan_profile(chat)
    message = chat.messages.find { |m| meal_plan_payload(m) }
    meal_plan_payload(message)["profile"] if message
  end

  # Sums kcal/protein/carbs/fat across a day's meals, using LIVE macros
  # (MealPlanMacros.live_macros — recomputed from each meal's current Recipe
  # data) rather than the figures frozen into the plan JSON at generation
  # time. This means editing a recipe's ingredients immediately shows up
  # here, in every past meal plan that uses it — not just future ones.
  def day_totals(day)
    meals = Array(day["meals"]).map { |meal| MealPlanMacros.live_macros(meal) }

    {
      kcal: meals.sum { |meal| meal["kcal"].to_i },
      protein_g: meals.sum { |meal| meal["protein_g"].to_i },
      carbs_g: meals.sum { |meal| meal["carbs_g"].to_i },
      fat_g: meals.sum { |meal| meal["fat_g"].to_i }
    }
  end

  # Recipes a given meal slot can be swapped to, matching the same
  # category rules as the meal-plan generator (lunch/dinner share the
  # "main" catalog; breakfast/snack are their own).
  def recipes_for_meal_type(meal_type)
    category = meal_type_category(meal_type)
    Recipe.where(category: category).includes(:recipe_ingredients, photo_attachment: :blob).order(:name)
  end

  # Distinct ingredient names known across every recipe, offered when adding
  # an extra ingredient to a specific meal (see MessagesController#add_ingredient).
  def available_ingredient_names
    RecipeIngredient.distinct.order(:name).pluck(:name)
  end

  private

  def meal_type_category(meal_type)
    %w[breakfast snack].include?(meal_type.to_s) ? meal_type.to_s : "main"
  end
end
