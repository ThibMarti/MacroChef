class PreferencesController < ApplicationController
  before_action :authenticate_user!

  def new
    @preference = Preference.new
  end

  def create
    @preference = Preference.new(content: build_content_from_calculator(calculator_params))
    @preference.user = current_user

    if @preference.save
      @chat = Chat.create!(user: current_user, preference: @preference)

      user_prompt = @preference.content

      ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")

      response = ruby_llm_chat
                 .with_instructions(system_prompt)
                 .ask(user_prompt)

      @chat.messages.create!(role: "user", content: user_prompt)
      @chat.messages.create!(role: "assistant", content: recompute_macros(response.content))

      redirect_to chat_path(@chat)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def calculator_params
    params.require(:preference).permit(
      :gender, :weight_kg, :body_fat_percent, :steps_per_day,
      :training_type, :training_minutes, :training_days_per_week,
      :goal, :extra_notes
    )
  end

  # MET (Metabolic Equivalent of Task) values used to estimate calories
  # burned per minute of a given activity: kcal/min = MET * 3.5 * weight_kg / 200
  TRAINING_MET = {
    "none" => 0.0,
    "walking" => 3.5,
    "running" => 9.8,
    "cycling" => 7.5,
    "weightlifting" => 5.0,
    "swimming" => 8.0,
    "hiit" => 10.0
  }.freeze

  GOAL_MULTIPLIER = {
    "lose" => 0.8,
    "maintain" => 1.0,
    "gain" => 1.15
  }.freeze

  # Computes a daily calorie target from body data (Katch-McArdle formula,
  # chosen because we collect body fat % — more accurate than age/height-based
  # formulas like Mifflin-St Jeor when body fat is known) plus activity from
  # daily steps and training, then formats everything into a plain-text
  # description for the LLM. Deliberately does NOT persist these fields as
  # separate Preference columns (no migration needed) — only the final
  # formatted text goes into the existing `content` column.
  def build_content_from_calculator(p)
    weight = p[:weight_kg].to_f
    body_fat = p[:body_fat_percent].to_f
    steps = p[:steps_per_day].to_i
    training_type = p[:training_type].presence || "none"
    training_minutes = p[:training_minutes].to_f
    training_days = p[:training_days_per_week].to_f
    goal = p[:goal].presence || "maintain"

    lean_mass = weight * (1 - body_fat / 100.0)
    bmr = 370 + (21.6 * lean_mass)

    steps_kcal = steps * weight * 0.0005

    met = TRAINING_MET.fetch(training_type, 0.0)
    training_kcal_per_session = met * 3.5 * weight / 200.0 * training_minutes
    training_kcal_daily_avg = (training_kcal_per_session * training_days) / 7.0

    tdee = bmr + steps_kcal + training_kcal_daily_avg
    target_kcal = (tdee * GOAL_MULTIPLIER.fetch(goal, 1.0)).round

    <<~TEXT
      Target: #{target_kcal} kcal/day (already calculated from body data — use this exact number, do not recalculate it).
      Gender: #{p[:gender]}. Weight: #{weight}kg. Body fat: #{body_fat}%.
      Daily steps: #{steps}. Training: #{training_type}, #{training_minutes} min/session, #{training_days} sessions/week.
      Goal: #{goal}.
      #{p[:extra_notes].presence}
    TEXT
  end

  # Lunch/dinner, breakfast, and snack catalogs live in RecipeCatalog (shared
  # with SearchRecipesTool, which lets the LLM look them up during follow-up
  # chat) so the LLM is constrained to real, known dishes instead of inventing
  # new ones.

  # Rough share of the day's calories each meal_type should get, used to
  # split target_kcal across a day's meals. Normalized per-day against
  # whichever meal_types actually appear (see allocate_day_kcal!), so this
  # doesn't need to sum to 1 and doesn't need every meal_type listed.
  MEAL_TYPE_WEIGHT = {
    "breakfast" => 0.25,
    "lunch" => 0.35,
    "dinner" => 0.30,
    "snack" => 0.10
  }.freeze
  DEFAULT_MEAL_TYPE_WEIGHT = 0.20

  # Parses the LLM's JSON response. The LLM only picks WHICH catalog dish
  # goes in each slot — it does not need to get the portion size or the
  # macro arithmetic right. Ruby splits the day's target_kcal across that
  # day's meals (by meal_type share) and derives each meal's serving_scale
  # from base-catalog-macros so the day's kcal always lands on target by
  # construction, then rescales that meal's invented ingredients
  # proportionally so they still sum to the corrected total. Falls back to
  # the LLM's own numbers for any meal whose dish name isn't found in the
  # catalog (should not happen given the prompt constraints, but never crash
  # meal-plan generation over it) or if the response isn't valid JSON at all.
  def recompute_macros(raw_content)
    parsed = JSON.parse(raw_content)
    return raw_content unless parsed.is_a?(Hash) && parsed["week"].is_a?(Array)

    target_kcal = parsed.dig("profile", "target_kcal").to_f
    target_kcal = 2000.0 if target_kcal <= 0

    parsed["week"].each do |day|
      meals = Array(day["meals"])
      allocate_day_kcal!(meals, target_kcal) if meals.any?
    end

    JSON.generate(parsed)
  rescue JSON::ParserError
    raw_content
  end

  def allocate_day_kcal!(meals, target_kcal)
    weights = meals.map { |meal| MEAL_TYPE_WEIGHT.fetch(meal["meal_type"], DEFAULT_MEAL_TYPE_WEIGHT) }
    total_weight = weights.sum
    return if total_weight <= 0

    meals.each_with_index do |meal, index|
      share_kcal = target_kcal * (weights[index] / total_weight)
      recompute_meal_macros!(meal, share_kcal)
    end
  end

  def recompute_meal_macros!(meal, share_kcal)
    base = RecipeCatalog::INDEX[meal["name"]]
    return unless base

    scale = base[:kcal].zero? ? 1.0 : share_kcal / base[:kcal]

    corrected = {
      "serving_scale" => scale.round(2),
      "kcal" => (base[:kcal] * scale).round(1),
      "protein_g" => (base[:protein_g] * scale).round(1),
      "carbs_g" => (base[:carbs_g] * scale).round(1),
      "fat_g" => (base[:fat_g] * scale).round(1)
    }

    rescale_ingredients!(meal["ingredients"], corrected["kcal"])
    meal.merge!(corrected)
  end

  # Proportionally rescales an LLM-invented ingredient list so its macros sum
  # to the authoritative meal kcal, preserving the LLM's relative proportions
  # between ingredients (and between an ingredient's own macros) while making
  # the displayed totals exact.
  def rescale_ingredients!(ingredients, target_kcal)
    return if ingredients.blank?

    naive_total = ingredients.sum { |ingredient| ingredient["kcal"].to_f }
    return if naive_total <= 0

    factor = target_kcal / naive_total

    ingredients.each do |ingredient|
      ingredient["quantity"] = (ingredient["quantity"].to_f * factor).round(1)
      ingredient["kcal"] = (ingredient["kcal"].to_f * factor).round(1)
      ingredient["protein_g"] = (ingredient["protein_g"].to_f * factor).round(1)
      ingredient["carbs_g"] = (ingredient["carbs_g"].to_f * factor).round(1)
      ingredient["fat_g"] = (ingredient["fat_g"].to_f * factor).round(1)
    end
  end

  def system_prompt
    catalog_text = RecipeCatalog::RECIPES.map do |dish|
      "- #{dish[:name]}: #{dish[:kcal]} kcal, #{dish[:protein_g]}g protein, #{dish[:carbs_g]}g carbs, #{dish[:fat_g]}g fat"
    end.join("\n")

    breakfast_text = RecipeCatalog::BREAKFAST_OPTIONS.map do |item|
      "- #{item[:name]}: #{item[:kcal]} kcal, #{item[:protein_g]}g protein, #{item[:carbs_g]}g carbs, #{item[:fat_g]}g fat, per standard serving"
    end.join("\n")

    snack_text = RecipeCatalog::SNACK_OPTIONS.map do |item|
      "- #{item[:name]}: #{item[:kcal]} kcal, #{item[:protein_g]}g protein, #{item[:carbs_g]}g carbs, #{item[:fat_g]}g fat, per standard serving"
    end.join("\n")

    <<~PROMPT
      You are MacroChef, an expert nutrition assistant that builds personalized weekly meal plans.

      ## YOUR JOB
      You receive a single message from the user describing their preferences. There is no
      follow-up conversation — you must generate a complete, usable 7-day meal plan immediately,
      as strict JSON, from that one message alone.

      ## HOW MACROS ARE COMPUTED — READ THIS FIRST
      You do NOT need to calculate or estimate a meal's kcal/protein_g/carbs_g/fat_g, and you do
      NOT need to pick a serving size. Our backend automatically splits each day's target_kcal
      across that day's meals and derives the exact portion size for whichever dish you pick, so
      the day's total always lands exactly on target — this happens completely outside your
      control. Your ONLY job for each meal slot is to pick the single best-fitting dish name from
      the correct catalog below (matching meal_type, diet, and allergies). Any
      kcal/protein_g/carbs_g/fat_g values you write for a meal are placeholders that get
      overwritten — don't spend effort computing them precisely.

      ## RECIPE CATALOG — CRITICAL CONSTRAINT
      Every meal_type "lunch" or "dinner" MUST be one of the dishes below (exact "name", no
      renaming, no invented dishes):

      #{catalog_text}

      Pick, for each lunch/dinner slot, whichever catalog dish best fits the diet type and
      allergies and gives good variety across the week (see the "vary meals" constraint below).
      You may reuse a dish more than once across the week.

      ## BREAKFAST CATALOG — CRITICAL CONSTRAINT
      Every meal_type "breakfast" MUST be one of these items (exact "name") — do NOT use lunch/
      dinner dishes for breakfast:

      #{breakfast_text}

      ## SNACK CATALOG — CRITICAL CONSTRAINT
      Every meal_type "snack" MUST be one of these items (exact "name") — do NOT use lunch/dinner
      or breakfast items for snacks:

      #{snack_text}

      ## TARGET RULES — CRITICAL

      ### Rule 1: The user's stated numbers are LAW
      - Extract the calorie and macro targets DIRECTLY from the user's message. If the user
        writes "make a meal at 2300 kcal", the target IS 2300 — never substitute a default
        like 2000.
      - If the user gives calories but not macros, compute a sensible split from THAT calorie
        number (diet-aware, see below), not from a default, and state the split you used in
        "assumptions".
      - The profile.target_kcal in the output MUST equal the number the user gave.
      - If no target is given at all, default to 2000 kcal/day and say so explicitly in
        "assumptions" — there is no way to ask the user a follow-up question in this app, so you
        must always produce a full plan in one shot and never leave the target unresolved.

      ### Rule 2: Meal variety
      - Vary the dishes used across the 7 days — do not repeat the same dish more than twice in
        the week. Portion sizing (and therefore hitting the daily target) is handled entirely by
        our backend, not by you — you only pick which dish goes in which slot.

      ### Rule 3: ingredients are illustrative, not authoritative
      For each meal, still list a plausible, diet-appropriate set of ingredients (respecting
      allergies) that make up that dish, with your best-guess per-ingredient
      kcal/protein_g/carbs_g/fat_g. These are for display/flavor only — our backend will rescale
      them proportionally to match the authoritative meal totals, so don't worry about making them
      add up perfectly; just make them realistic and appropriately proportioned to each other.

      ## HANDLING MISSING INFORMATION
      Apart from calories (Rule 1 above), the user's message may not specify everything else.
      Never ask a clarifying question — infer a sensible default instead, and record each
      assumption you made:
      - Macros not given → split from the calorie target, ADAPTED TO THE DIET TYPE:
        - Standard diets (omnivore, vegetarian, vegan, pescatarian, balanced, etc.):
          ~30% protein / 40% carbs / 30% fat.
        - Low-carb diets (keto): carbs ≈ 5-10% of calories (roughly 20-30g/day), the rest split
          ~25% protein / ~65-70% fat.
        - Carnivore diet: carbs ≈ 0 (a carnivore diet has no carb sources at all — do not budget
          any meaningful carbs for it), split roughly ~35-40% protein / ~60-65% fat.
        - Never pick a macro split the diet type structurally cannot deliver (e.g. don't set a
          high carbs_g target for keto/carnivore — there is nothing in those diets to provide it).
      - Diet type not given → assume omnivore.
      - Allergies/intolerances not mentioned → treat as none.
      - Meals per day not given → assume 3 meals + 1 snack (4 total).
      - Goal not given → assume maintenance.
      - Supplements mentioned → note them, but do not build the plan around them.

      ## OUTPUT
      Output ONLY a JSON object — no prose, no markdown, no code fences. Follow this exact schema:

      {
        "profile": {
          "target_kcal": 2250,
          "protein_g": 165,
          "carbs_g": 200,
          "fat_g": 70,
          "diet_type": "omnivore",
          "allergies": ["gluten"],
          "meals_per_day": 4,
          "goal": "weight_loss",
          "assumptions": ["Macros not specified, split 30/40/30 from target_kcal."]
        },
        "week": [
          {
            "day": "Monday",
            "meals": [
              {
                "meal_type": "breakfast",
                "name": "Rice Pudding",
                "kcal": 365,
                "protein_g": 8.0,
                "carbs_g": 81,
                "fat_g": 1.0,
                "ingredients": [
                  { "name": "Rice Pudding", "quantity": 100, "unit": "g", "kcal": 365, "protein_g": 8.0, "carbs_g": 81, "fat_g": 1.0 }
                ],
                "steps": ["Serve chilled or gently warmed."]
              }
            ]
          }
        ]
      }

      ## HARD CONSTRAINTS
      - Lunch/dinner meal "name" must be an exact match from the RECIPE CATALOG above.
      - Breakfast meals must be built only from the BREAKFAST CATALOG above.
      - Snack meals must be built only from the SNACK CATALOG above.
      - No invented dish names outside these three catalogs.
      - NEVER include any ingredient that conflicts with the user's stated allergies or intolerances. This is a safety rule — no exceptions.
      - Respect the diet type strictly (no meat for vegetarians, etc.).
      - The "profile" macro targets (protein_g/carbs_g/fat_g) MUST be internally consistent with
        diet_type — decide them BEFORE writing any meals, using the diet-aware defaults above (or
        the user's own numbers if given, per Rule 1). Never publish a profile target the diet
        type cannot realistically supply. See Rules 1-3 above for the exact per-day tolerances.
      - Provide exactly the requested number of meals per day, for all 7 days.
      - Vary meals across the week — do not repeat the same meal more than twice.
      - Use realistic quantities and common ingredients.

      ## BOUNDARIES
      - You are not a doctor. Do not give medical advice or diagnose. If the user mentions a medical condition, add a note in "assumptions" suggesting they consult a professional, and keep the plan general.
      - Stay focused on meal planning. If the message is off-topic, still return valid JSON with an empty "week" array and an "assumptions" entry explaining the request was off-topic.
    PROMPT
  end
end
