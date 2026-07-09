class SearchRecipesTool < RubyLLM::Tool
  description <<~DESC
    Search MacroChef's curated catalog of lunch/dinner dishes, breakfasts, and
    snacks. Use this during follow-up conversation to check a dish's exact
    macros before mentioning it, or to find catalog options that fit a
    calorie/protein target — never invent dish names or macros from memory.
  DESC

  param :meal_type, type: "string",
                     desc: "Filter by meal type: lunch, dinner, breakfast, or snack. Omit to search all.",
                     required: false
  param :query, type: "string",
                desc: "Keyword to match against dish names (case-insensitive substring match).",
                required: false
  param :max_kcal, type: "integer",
                    desc: "Upper bound on kcal per standard serving.",
                    required: false
  param :min_protein_g, type: "integer",
                         desc: "Lower bound on protein grams per standard serving.",
                         required: false

  def execute(meal_type: nil, query: nil, max_kcal: nil, min_protein_g: nil)
    dishes = RecipeCatalog.for_meal_type(meal_type)
    dishes = dishes.select { |dish| dish[:name].downcase.include?(query.downcase) } if query.present?
    dishes = dishes.select { |dish| dish[:kcal] <= max_kcal.to_f } if max_kcal.present?
    dishes = dishes.select { |dish| dish[:protein_g] >= min_protein_g.to_f } if min_protein_g.present?

    return "No catalog dishes matched those filters." if dishes.empty?

    dishes.map { |dish| format_dish(dish) }.join("\n")
  end

  private

  def format_dish(dish)
    "#{dish[:name]}: #{dish[:kcal]} kcal, #{dish[:protein_g]}g protein, " \
      "#{dish[:carbs_g]}g carbs, #{dish[:fat_g]}g fat (per standard serving)"
  end
end
