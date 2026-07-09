# Curated catalog of real, tested dish concepts (generic dish names/macros —
# no branded product names, no pricing/review data, no photos). Shared between
# PreferencesController (constrains the initial meal-plan generation) and
# SearchRecipesTool (lets the LLM look up catalog dishes during follow-up chat).
module RecipeCatalog
  RECIPES = [
    { name: "Paella", kcal: 490, protein_g: 40, carbs_g: 45, fat_g: 15 },
    { name: "Vegan Protein Pasta Bolognese", kcal: 552, protein_g: 41, carbs_g: 75, fat_g: 7 },
    { name: "Buffalo-Style Chicken Bowl", kcal: 460, protein_g: 41, carbs_g: 43, fat_g: 11 },
    { name: "Roasted Potatoes with Chicken", kcal: 410, protein_g: 43, carbs_g: 40, fat_g: 8 },
    { name: "Cheese Spätzle with Chicken", kcal: 690, protein_g: 55, carbs_g: 70, fat_g: 21 },
    { name: "Protein Pasta Alfredo", kcal: 580, protein_g: 60, carbs_g: 60, fat_g: 10 },
    { name: "Protein Pasta with Salmon", kcal: 565, protein_g: 47, carbs_g: 73, fat_g: 8 },
    { name: "Chili con Carne", kcal: 600, protein_g: 35, carbs_g: 55, fat_g: 23 },
    { name: "Butter Chicken", kcal: 625, protein_g: 45, carbs_g: 66, fat_g: 19 },
    { name: "Chicken Fajita Bowl", kcal: 550, protein_g: 55, carbs_g: 58, fat_g: 11 },
    { name: "Asian Style Noodles", kcal: 510, protein_g: 48, carbs_g: 48, fat_g: 12 },
    { name: "Protein Pasta Bolognese", kcal: 630, protein_g: 43, carbs_g: 75, fat_g: 16 },
    { name: "Pollock with Rice and Vegetables", kcal: 395, protein_g: 32, carbs_g: 36, fat_g: 13 },
    { name: "Red Thai Curry", kcal: 555, protein_g: 43, carbs_g: 47, fat_g: 21 },
    { name: "Protein Pasta with Cream Cheese Sauce", kcal: 590, protein_g: 32, carbs_g: 70, fat_g: 19 },
    { name: "Chicken, Rice and Broccoli", kcal: 455, protein_g: 42, carbs_g: 59, fat_g: 5 },
    { name: "Sweet Potato Chicken Bowl", kcal: 405, protein_g: 41, carbs_g: 36, fat_g: 9 },
    { name: "Thai Chicken Bowl", kcal: 330, protein_g: 50, carbs_g: 13, fat_g: 7 },
    { name: "Protein Pizza Margherita", kcal: 784, protein_g: 50, carbs_g: 113, fat_g: 12 },
    { name: "Protein Pizza Chicken & Peppers", kcal: 885, protein_g: 65, carbs_g: 120, fat_g: 15 },
    { name: "Tikka Masala", kcal: 630, protein_g: 46, carbs_g: 60, fat_g: 22 },
    { name: "Protein Penne with Veggie Bolognese", kcal: 616, protein_g: 38, carbs_g: 69, fat_g: 18 },
    { name: "Asian Noodles with Beef", kcal: 581, protein_g: 32, carbs_g: 67, fat_g: 19 },
    { name: "Philly Cheese & Beef Bowl", kcal: 543, protein_g: 35, carbs_g: 35, fat_g: 28 },
    { name: "Chicken Döner-Style", kcal: 597, protein_g: 46, carbs_g: 56, fat_g: 20 },
    { name: "Linguine Aglio e Olio", kcal: 691, protein_g: 45, carbs_g: 89, fat_g: 16 },
    { name: "Gnocchi with Salmon", kcal: 653, protein_g: 36, carbs_g: 58, fat_g: 29 },
    { name: "Rice Noodles in Coconut Sauce", kcal: 605, protein_g: 45, carbs_g: 50, fat_g: 25 },
    { name: "Lasagne", kcal: 603, protein_g: 44, carbs_g: 44, fat_g: 29 },
    { name: "Vegetable Lasagne", kcal: 645, protein_g: 34, carbs_g: 80, fat_g: 19 },
    { name: "Burrito Bowl", kcal: 625, protein_g: 45, carbs_g: 70, fat_g: 18 },
    { name: "Mac & Cheese with Chicken", kcal: 755, protein_g: 44, carbs_g: 71, fat_g: 32 },
    { name: "Salmon with Pumpkin Purée", kcal: 720, protein_g: 36, carbs_g: 23, fat_g: 52 },
    { name: "Vegan Green Curry", kcal: 667, protein_g: 30, carbs_g: 60, fat_g: 32 },
    { name: "Chicken with Hummus", kcal: 711, protein_g: 49, carbs_g: 22, fat_g: 45 },
    { name: "Cheeseburger Bowl", kcal: 555, protein_g: 39, carbs_g: 20, fat_g: 34 },
    { name: "Chickpea Masala", kcal: 404, protein_g: 12, carbs_g: 48, fat_g: 14 },
    { name: "Vegan Biryani", kcal: 595, protein_g: 14, carbs_g: 90, fat_g: 18 }
  ].freeze

  # Breakfast options, each given as ONE STANDARD SERVING (same convention as
  # RECIPES) so every catalog can be scaled the same way.
  BREAKFAST_OPTIONS = [
    { name: "Rice Flour Crêpes", kcal: 583, protein_g: 26.7, carbs_g: 80.2, fat_g: 17.1 },
    { name: "Rice Pudding", kcal: 365, protein_g: 8.0, carbs_g: 81, fat_g: 1.0 },
    { name: "Rice Crispies", kcal: 389, protein_g: 7.2, carbs_g: 83, fat_g: 2.4 }
  ].freeze

  # Snack options, each given as ONE STANDARD SERVING (100g, or 100g-equivalent
  # for the protein bar) using standard, well-known macros for the plain items.
  SNACK_OPTIONS = [
    { name: "Skyr", kcal: 63, protein_g: 11, carbs_g: 4, fat_g: 0.2 },
    { name: "Quark (Magerquark)", kcal: 67, protein_g: 12, carbs_g: 4, fat_g: 0.2 },
    { name: "Whey Protein", kcal: 380, protein_g: 80, carbs_g: 8, fat_g: 4 },
    { name: "Fresh Fruit", kcal: 55, protein_g: 0.5, carbs_g: 14, fat_g: 0.2 },
    { name: "Almonds", kcal: 579, protein_g: 21, carbs_g: 22, fat_g: 50 },
    { name: "Cashews", kcal: 553, protein_g: 18, carbs_g: 30, fat_g: 44 },
    { name: "Protein Bar", kcal: 373, protein_g: 32, carbs_g: 39, fat_g: 15 }
  ].freeze

  # Combined name → base-serving-macros lookup used to recompute a meal's real
  # macros in Ruby rather than trusting the LLM's own arithmetic.
  INDEX = (RECIPES + BREAKFAST_OPTIONS + SNACK_OPTIONS)
          .each_with_object({}) { |dish, index| index[dish[:name]] = dish }
          .freeze

  def self.for_meal_type(meal_type)
    case meal_type.to_s.downcase
    when "breakfast" then BREAKFAST_OPTIONS
    when "snack" then SNACK_OPTIONS
    when "lunch", "dinner" then RECIPES
    else RECIPES + BREAKFAST_OPTIONS + SNACK_OPTIONS
    end
  end
end
