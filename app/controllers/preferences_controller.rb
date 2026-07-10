class PreferencesController < ApplicationController
  before_action :authenticate_user!

  def new
    @preference = Preference.new
  end

  # Step 1: compute target_kcal and a default macro split from body data,
  # then show the user those exact numbers (editable) to confirm or adjust
  # before we spend an LLM call generating the actual plan.
  def create
    p = calculator_params
    @target_kcal = compute_target_kcal(p)
    lean_mass = p[:weight_kg].to_f * (1 - p[:body_fat_percent].to_f / 100.0)

    default_macros = default_macro_split(@target_kcal, p[:weight_kg].to_f, lean_mass)
    @protein_g = default_macros[:protein_g]
    @carbs_g = default_macros[:carbs_g]
    @fat_g = default_macros[:fat_g]

    @calculator_params = p
  end

  # Step 2: the user has confirmed (or edited) protein_g/carbs_g/fat_g on the
  # previous screen, then we actually generate the plan via the LLM.
  # target_kcal is always re-derived from those three grams here in Ruby
  # (protein_g*4 + carbs_g*4 + fat_g*9) rather than trusted from the client
  # — the confirm page's live kcal display is JS convenience only.
  def generate
    p = calculator_params
    protein_g = params[:protein_g].to_i
    carbs_g = params[:carbs_g].to_i
    fat_g = params[:fat_g].to_i
    target_kcal = (protein_g * 4) + (carbs_g * 4) + (fat_g * 9)
    recurring = recurring_recipes(p)

    @preference = Preference.new(content: build_content(p, target_kcal, protein_g, carbs_g, fat_g, recurring))
    @preference.user = current_user

    if @preference.save
      @chat = Chat.create!(user: current_user, preference: @preference)

      user_prompt = @preference.content
      favorite_recipe_ids = p[:only_favorites] == "1" ? current_user.favorite_recipes.ids : nil
      plan_json = ask_llm_for_plan(user_prompt, favorite_recipe_ids, recurring)

      @chat.messages.create!(role: "user", content: user_prompt)
      @chat.messages.create!(role: "assistant", content: recompute_macros(plan_json, favorite_recipe_ids, recurring))

      redirect_to chat_path(@chat)
    else
      redirect_to new_preference_path, alert: @preference.errors.full_messages.to_sentence
    end
  end

  private

  # Calls the LLM for a plan, retrying once if the response isn't valid
  # JSON with a "week" array — small models occasionally emit slightly
  # malformed JSON (stray comma, unescaped character, etc.), especially for
  # larger plans (5+ meals/day). Returns whichever attempt's raw content
  # looked valid, or the last attempt if both failed (recompute_macros
  # degrades gracefully either way, but this makes success the common case).
  def ask_llm_for_plan(user_prompt, favorite_recipe_ids, recurring)
    2.times do |attempt|
      ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
      response = ruby_llm_chat
                 .with_instructions(system_prompt(favorite_recipe_ids, recurring))
                 .ask(user_prompt)

      parsed = JSON.parse(response.content) rescue nil
      return response.content if parsed.is_a?(Hash) && parsed["week"].is_a?(Array)

      return response.content if attempt == 1
    end
  end

  def calculator_params
    params.require(:preference).permit(
      :gender, :weight_kg, :body_fat_percent, :steps_per_day,
      :training_type, :training_minutes, :training_days_per_week,
      :goal, :extra_notes, :only_favorites,
      :recurring_breakfast_id, :recurring_lunch_id, :recurring_dinner_id,
      :recurring_snack_1_id, :recurring_snack_2_id
    )
  end

  # Builds { "breakfast" => Recipe, "lunch" => Recipe, "dinner" => Recipe,
  # "snack" => [Recipe, Recipe] } from whichever recurring_*_id fields the
  # user filled in — meal types with no selection are absent from the hash.
  # Snack is a list (not a single Recipe) since a day can have more than one
  # snack slot: apply_recurring_meals! matches list position to the Nth
  # snack of the day (Snack 1 -> first snack meal, Snack 2 -> second).
  def recurring_recipes(p)
    recurring = %w[breakfast lunch dinner].filter_map do |meal_type|
      recipe = Recipe.find_by(id: p[:"recurring_#{meal_type}_id"])
      [meal_type, recipe] if recipe
    end.to_h

    snacks = [p[:recurring_snack_1_id], p[:recurring_snack_2_id]].map { |id| Recipe.find_by(id: id) }
    recurring["snack"] = snacks if snacks.any?

    recurring
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
  # daily steps and training. Deliberately does NOT persist these fields as
  # separate Preference columns (no migration needed).
  def compute_target_kcal(p)
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
    (tdee * GOAL_MULTIPLIER.fetch(goal, 1.0)).round
  end

  # Default macro split shown (as editable percentages) on the confirm step:
  # ~2g protein per kg of lean (fat-free) mass, ~1g fat per kg of total
  # bodyweight, and carbs fill whatever's left of the calorie target. The
  # user can override the resulting percentages before generation.
  def default_macro_split(target_kcal, weight, lean_mass)
    protein_g = (2 * lean_mass).round
    fat_g = weight.round
    carbs_kcal = target_kcal - (protein_g * 4) - (fat_g * 9)
    carbs_g = [(carbs_kcal / 4.0).round, 0].max

    { protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g }
  end

  # Formats the final (possibly user-edited) target/macros plus the rest of
  # the calculator inputs into the plain-text description sent to the LLM.
  # If the user pinned a "Snack 2" recurring meal, explicitly tells the LLM
  # to include 2 snacks/day — otherwise the default (1 snack/day, see
  # system_prompt) would leave that second recurring pick with no slot to
  # ever land in.
  def build_content(p, target_kcal, protein_g, carbs_g, fat_g, recurring = {})
    snack_count = recurring["snack"].is_a?(Array) ? recurring["snack"].compact.count : 0

    <<~TEXT
      Target: #{target_kcal} kcal/day (already calculated from body data — use this exact number, do not recalculate it).
      Macros: #{protein_g}g protein, #{carbs_g}g carbs, #{fat_g}g fat (already calculated from body data — use
      these exact numbers, do not recalculate them, unless the notes below explicitly override them).
      Gender: #{p[:gender]}. Weight: #{p[:weight_kg]}kg. Body fat: #{p[:body_fat_percent]}%.
      Daily steps: #{p[:steps_per_day]}. Training: #{p[:training_type].presence || "none"}, #{p[:training_minutes]} min/session, #{p[:training_days_per_week]} sessions/week.
      Goal: #{p[:goal].presence || "maintain"}.
      #{"Include exactly #{snack_count} snacks per day (not the default 1) IN ADDITION TO breakfast, lunch, and dinner — never drop breakfast/lunch/dinner to make room for extra snacks. The user has #{snack_count} recurring snack slots configured." if snack_count > 1}
      #{p[:extra_notes].presence}
    TEXT
  end

  # Lunch/dinner, breakfast, and snack catalogs live in RecipeCatalog (shared
  # with SearchRecipesTool, which lets the LLM look them up during follow-up
  # chat) so the LLM is constrained to real, known dishes instead of inventing
  # new ones. The actual macro math lives in MealPlanMacros (shared with
  # MessagesController#swap_meal, which replaces one dish in an existing plan).

  # Parses the LLM's JSON response. The LLM only picks WHICH catalog dish
  # goes in each slot — it does not need to get the portion size or the
  # macro arithmetic right. MealPlanMacros splits each day's target_kcal
  # across that day's meals (by meal_type share) and derives each meal's
  # serving_scale from base-catalog-macros so the day's kcal always lands on
  # target by construction, then rescales that meal's invented ingredients
  # proportionally so they still sum to the corrected total. Falls back to
  # the LLM's own numbers for any meal whose dish name isn't found in the
  # catalog (should not happen given the prompt constraints, but never crash
  # meal-plan generation over it) or if the response isn't valid JSON at all.
  #
  # When favorite_recipe_ids is given, also enforces the "only favorites"
  # restriction ourselves (see enforce_favorites!) rather than trusting the
  # LLM to have honored it — small models sometimes pick a dish outside the
  # given catalog anyway despite the prompt's hard constraint. Likewise,
  # `recurring` ({ "breakfast" => Recipe, ... }) forces every meal of that
  # meal_type, every day, to be that exact recipe — same "never trust the
  # LLM to honor a prompt instruction, enforce it in Ruby" pattern.
  def recompute_macros(raw_content, favorite_recipe_ids = nil, recurring = {})
    parsed = JSON.parse(raw_content)
    return raw_content unless parsed.is_a?(Hash) && parsed["week"].is_a?(Array)

    target_kcal = parsed.dig("profile", "target_kcal").to_f
    target_kcal = 2000.0 if target_kcal <= 0

    # Built once and reused for every meal in the plan — see the comment on
    # MealPlanMacros.allocate_day! for why this matters.
    recipe_by_name = Recipe.includes(:recipe_ingredients).index_by(&:name)
    favorites_catalog_cache = {}

    parsed["week"].each do |day|
      meals = Array(day["meals"])
      apply_recurring_meals!(meals, recurring) if recurring.present?
      enforce_favorites!(meals, favorite_recipe_ids, favorites_catalog_cache) if favorite_recipe_ids.present?
      ensure_core_meals!(meals, recurring, recipe_by_name)
      reorder_meals!(meals)
      MealPlanMacros.allocate_day!(meals, target_kcal, recipe_by_name) if meals.any?
    end

    JSON.generate(parsed)
  rescue JSON::ParserError
    raw_content
  end

  # Forces every meal whose meal_type has a recurring pick (e.g. "always
  # Rice Pudding for breakfast") to that exact recipe's name, regardless of
  # what the LLM chose — the actual macros/ingredients get (re)built from it
  # afterward by MealPlanMacros.allocate_day!, same as any other meal.
  #
  # breakfast/lunch/dinner map to a single Recipe (applies to the first meal
  # of that type in the day). snack maps to a list — position N applies to
  # the Nth snack of the day (Snack 1 -> first snack, Snack 2 -> second), so
  # each snack slot can be pinned independently; a nil entry means "no
  # preference for that slot" and leaves the LLM's choice alone.
  def apply_recurring_meals!(meals, recurring)
    occurrence = Hash.new(0)

    meals.each do |meal|
      meal_type = meal["meal_type"]
      index = occurrence[meal_type]
      occurrence[meal_type] += 1

      pick = recurring[meal_type]
      recipe = pick.is_a?(Array) ? pick[index] : (pick if index.zero?)
      meal["name"] = recipe.name if recipe
    end

    # The LLM sometimes still only generates 1 snack/day despite the
    # "include N snacks" instruction in the user prompt (small models don't
    # reliably honor prompt instructions) — if a recurring slot has no meal
    # to land in, add it directly rather than silently losing that pin.
    recurring.each do |meal_type, pick|
      next unless pick.is_a?(Array)

      pick.each_with_index do |recipe, index|
        next unless recipe
        next if index < occurrence[meal_type]

        meals << { "meal_type" => meal_type, "name" => recipe.name, "ingredients" => [], "steps" => [] }
      end
    end

    # Conversely, trim any EXTRA meals of a recurring meal_type beyond the
    # configured count — the LLM sometimes adds more than requested despite
    # the explicit "include exactly N snacks" instruction. The first
    # `expected` occurrences are already correctly pinned above, so it's
    # always the trailing extras that get dropped.
    recurring.each do |meal_type, pick|
      next unless pick.is_a?(Array)

      expected = pick.compact.count
      seen = 0
      meals.reject! do |meal|
        next false unless meal["meal_type"] == meal_type

        seen += 1
        seen > expected
      end
    end
  end

  # Guarantees breakfast/lunch/dinner each appear at least once per day —
  # small models sometimes drop one of the core meals (e.g. swap dinner out
  # to make room for an extra snack) despite the prompt saying not to.
  # Missing slots are filled with the user's recurring pick for that
  # meal_type if configured, otherwise the first catalog recipe available.
  def ensure_core_meals!(meals, recurring, recipe_by_name)
    %w[breakfast lunch dinner].each do |meal_type|
      next if meals.any? { |meal| meal["meal_type"] == meal_type }

      pick = recurring[meal_type]
      recipe = pick.is_a?(Recipe) ? pick : fallback_recipe_for(meal_type, recipe_by_name)
      next unless recipe

      meals << { "meal_type" => meal_type, "name" => recipe.name, "ingredients" => [], "steps" => [] }
    end
  end

  def fallback_recipe_for(meal_type, recipe_by_name)
    category = meal_type == "breakfast" ? "breakfast" : "main"
    recipe_by_name.values.find { |recipe| recipe.category == category }
  end

  # Reorders a day's meals into a fixed, predictable sequence: Breakfast,
  # (1st) Snack, Lunch, (2nd) Snack, Dinner — any further meals (extra
  # snacks etc.) are appended after, in their original relative order.
  def reorder_meals!(meals)
    snacks_seen = 0
    keyed = meals.map do |meal|
      key = case meal["meal_type"]
            when "breakfast" then 0
            when "snack"
              position = snacks_seen < 2 ? [1, 3][snacks_seen] : 10 + snacks_seen
              snacks_seen += 1
              position
            when "lunch" then 2
            when "dinner" then 4
            else 20
            end
      [key, meal]
    end

    meals.replace(keyed.sort_by(&:first).map(&:last))
  end

  # Replaces any meal whose dish isn't in the user's favorites (for that
  # meal_type) with one that is, picked from the same restricted catalog the
  # LLM was given — guarantees the "only use my favorites" option is always
  # honored regardless of whether the LLM actually followed the instruction.
  # `cache` memoizes the (at most 3) per-meal_type catalogs across the whole
  # week instead of rebuilding them for every single meal.
  def enforce_favorites!(meals, favorite_recipe_ids, cache = {})
    meals.each do |meal|
      allowed = cache[meal["meal_type"]] ||= catalog_for_meal_type(meal["meal_type"], favorite_recipe_ids)
      next if allowed.any? { |dish| dish[:name] == meal["name"] }

      replacement = allowed.sample
      meal["name"] = replacement[:name] if replacement
    end
  end

  def catalog_for_meal_type(meal_type, favorite_recipe_ids)
    case meal_type.to_s
    when "breakfast" then RecipeCatalog.breakfast_options(recipe_ids: favorite_recipe_ids)
    when "snack" then RecipeCatalog.snack_options(recipe_ids: favorite_recipe_ids)
    else RecipeCatalog.recipes(recipe_ids: favorite_recipe_ids)
    end
  end

  def system_prompt(favorite_recipe_ids = nil, recurring = {})
    # IMPORTANT: never write a compound label like "snack #1" here — models
    # have previously copied that whole string into the JSON "meal_type"
    # field verbatim (producing "snack #1" instead of "snack"), corrupting
    # the plan. "meal_type" must ALWAYS be exactly "snack" for these.
    recurring_text = recurring.flat_map do |meal_type, pick|
      if pick.is_a?(Array)
        ordinals = ["1st", "2nd", "3rd", "4th"]
        pick.each_with_index.filter_map do |recipe, index|
          "- The #{ordinals[index] || "#{index + 1}th"} \"#{meal_type}\" meal_type of the day: always \"#{recipe.name}\" " \
            "(the JSON \"meal_type\" field must still be exactly \"#{meal_type}\", not anything else)" if recipe
        end
      else
        ["- Every \"#{meal_type}\" meal_type: always \"#{pick.name}\""]
      end
    end.join("\n")

    catalog_text = RecipeCatalog.recipes(recipe_ids: favorite_recipe_ids).map do |dish|
      "- #{dish[:name]}: #{dish[:kcal]} kcal, #{dish[:protein_g]}g protein, #{dish[:carbs_g]}g carbs, #{dish[:fat_g]}g fat"
    end.join("\n")

    breakfast_text = RecipeCatalog.breakfast_options(recipe_ids: favorite_recipe_ids).map do |item|
      "- #{item[:name]}: #{item[:kcal]} kcal, #{item[:protein_g]}g protein, #{item[:carbs_g]}g carbs, #{item[:fat_g]}g fat, per standard serving"
    end.join("\n")

    snack_text = RecipeCatalog.snack_options(recipe_ids: favorite_recipe_ids).map do |item|
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

      #{"## RECURRING MEALS — CRITICAL CONSTRAINT\nThe user has locked these meal_types to always use the same dish, every day of the week — use exactly this dish for every meal of that meal_type, all 7 days (still fill in a plausible ingredient list per Rule 3 below):\n\n#{recurring_text}\n" if recurring_text.present?}
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
      - Extract the calorie and macro targets DIRECTLY from the user's message. The calculator
        form always provides a "Target: X kcal/day" line AND a "Macros: Xg protein, Xg carbs,
        Xg fat" line — these are computed from the user's real body data (weight, body fat %) in
        Ruby, not guessed, so use them exactly as given and do not recompute them.
      - If the user's own notes explicitly state a different target, macro split, or diet that
        structurally conflicts with the given macros (e.g. "keto" with the given carbs_g too
        high for keto), their explicit notes override the calculated numbers — but this should be
        rare, since the calculated macros are the default source of truth.
      - The profile.target_kcal/protein_g/carbs_g/fat_g in the output MUST equal the numbers given
        (or the user's explicit override, per above).
      - If no target/macros are given at all (should not normally happen), default to 2000 kcal/day
        with a 30/40/30 split and say so explicitly in "assumptions" — there is no way to ask the
        user a follow-up question in this app, so you must always produce a full plan in one shot
        and never leave the target unresolved.

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
      Apart from calories and macros (Rule 1 above — normally always given by the calculator),
      the user's message may not specify everything else. Never ask a clarifying question — infer
      a sensible default instead, and record each assumption you made:
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
          "assumptions": ["Diet type not specified, assumed omnivore."]
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
      - The "profile" macro targets (protein_g/carbs_g/fat_g) MUST equal the calculated macros
        given in the user's message (per Rule 1) unless their own notes explicitly override them.
        See Rules 1-3 above for the exact per-day tolerances.
      - Provide exactly the requested number of meals per day, for all 7 days.
      - Vary meals across the week — do not repeat the same meal more than twice.
      - Use realistic quantities and common ingredients.

      ## BOUNDARIES
      - You are not a doctor. Do not give medical advice or diagnose. If the user mentions a medical condition, add a note in "assumptions" suggesting they consult a professional, and keep the plan general.
      - Stay focused on meal planning. If the message is off-topic, still return valid JSON with an empty "week" array and an "assumptions" entry explaining the request was off-topic.
    PROMPT
  end
end
