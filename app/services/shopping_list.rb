# Builds a grocery/shopping list for a chat's meal plan: every ingredient
# across the whole week, summed by name (grams) and grouped by food type,
# using LIVE macros (MealPlanMacros.live_macros) so quantity edits and
# recipe changes are reflected — never the potentially-stale figures frozen
# in the plan JSON.
module ShoppingList
  Item = Struct.new(:name, :label, keyword_init: true)

  # Ordered [category, pattern] rules — first match wins, so more specific
  # categories (sauces, dairy) are checked before broader ones (carbs,
  # produce). Anything matching nothing lands in "Other".
  CATEGORY_RULES = [
    ["Supplements", /whey|protein bar|protein powder/i],
    ["Sauces, spices", /sauce|spice|\boil\b|herb/i],
    ["Yogurt, cheese", /cheese|mozzarella|yogh?urt|skyr|quark|\bmilk\b/i],
    ["Meat, fish", /chicken|beef|pork|turkey|salmon|pollock|shrimp|fish|egg/i],
    ["Carbs", /\brice\b|pasta|potato|noodle|pizza (dough|base)|tortilla|bread|sp.tzle|lasagne|gnocchi|\boat|sugar/i],
    ["Vegetables, fruit", /vegetable|fruit|apple|banana|broccoli|pepper|onion|pumpkin|bean|chickpea|hummus|lentil|tomato|tofu|almond|cashew|nut/i]
  ].freeze
  CATEGORY_ORDER = (CATEGORY_RULES.map(&:first) + ["Other"]).freeze

  # Items you'd actually count out at the store (produce, eggs) rather than
  # weigh — shown as "2 Broccoli" instead of "612 g Broccoli". Values are an
  # average grams-per-piece used to convert the summed grams into a count.
  PIECE_ITEMS = {
    /broccoli/i => 300,
    /\bapple\b/i => 180,
    /banana/i => 120,
    /bell pepper/i => 150,
    /\bonion\b/i => 110,
    /sweet potato/i => 200,
    /\btomato\b(?!.*sauce)/i => 120,
    /avocado/i => 200
  }.freeze

  # Items sold in fixed-size tubs/bags — the total is rounded UP to the
  # nearest multiple of the pack size, since you can't buy 43g of skyr, only
  # whole 250g tubs (so 3 tubs = "750 g", not the raw "43 g" you'd need).
  PACK_ITEMS = {
    /skyr|quark|yogh?urt/i => 250,
    /mozzarella/i => 125,
    /cheddar cheese\b/i => 200,
    /\brice\b|pasta|rice flour|noodle|gnocchi|lasagne|sp.tzle|tortilla/i => 500,
    /\bsauce\b/i => 200,
    /hummus/i => 200,
    /protein bar/i => 60
  }.freeze

  def self.category_for(name)
    CATEGORY_RULES.each { |category, pattern| return category if name.match?(pattern) }
    "Other"
  end

  # Formats a summed quantity the way you'd actually shop for it: a count
  # for produce/eggs, a rounded-up pack size for tubs/bags, or plain grams
  # for everything else (meat, sauces bought loose, etc).
  def self.label_for(name, quantity_g)
    PIECE_ITEMS.each do |pattern, avg_g|
      next unless name.match?(pattern)

      count = [(quantity_g / avg_g.to_f).ceil, 1].max
      return "#{count} #{name}"
    end

    PACK_ITEMS.each do |pattern, pack_g|
      next unless name.match?(pattern)

      rounded_g = [(quantity_g / pack_g.to_f).ceil, 1].max * pack_g
      return "#{rounded_g} g #{name}"
    end

    "#{quantity_g.round} g #{name}"
  end

  # Returns an ordered array of [category, [Item, ...]] — only categories
  # with at least one item, in CATEGORY_ORDER.
  def self.grouped_for_chat(chat)
    totals = Hash.new(0.0)

    message = chat.messages.find { |m| meal_plan(m) }
    return [] unless message

    meal_plan(message)["week"].each do |day|
      Array(day["meals"]).each do |meal|
        live = MealPlanMacros.live_macros(meal)
        Array(live["ingredients"]).each do |ingredient|
          totals[ingredient["name"]] += ingredient["quantity"].to_f
        end
      end
    end

    items_by_category = Hash.new { |h, k| h[k] = [] }
    totals.each do |name, quantity_g|
      items_by_category[category_for(name)] << Item.new(name: name, label: label_for(name, quantity_g))
    end

    CATEGORY_ORDER.filter_map do |category|
      items = items_by_category[category]
      [category, items.sort_by(&:name)] if items.present?
    end
  end

  def self.meal_plan(message)
    return nil unless message.role == "assistant"

    parsed = JSON.parse(message.content)
    parsed if parsed.is_a?(Hash) && parsed["week"].present?
  rescue JSON::ParserError
    nil
  end
end
