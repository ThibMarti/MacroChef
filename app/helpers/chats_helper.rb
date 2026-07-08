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

  # Sums kcal/protein/carbs/fat across a day's meals. Computed here from the
  # actual meal data (not trusted from the LLM's own totals), so it's always
  # accurate — useful to spot-check whether the day really matches the
  # profile targets.
  def day_totals(day)
    meals = Array(day["meals"])

    {
      kcal: meals.sum { |meal| meal["kcal"].to_i },
      protein_g: meals.sum { |meal| meal["protein_g"].to_i },
      carbs_g: meals.sum { |meal| meal["carbs_g"].to_i },
      fat_g: meals.sum { |meal| meal["fat_g"].to_i }
    }
  end
end
