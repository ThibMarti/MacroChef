# One-off script (not part of db:seed) that replaces each main-dish recipe's
# single placeholder ingredient with a realistic multi-ingredient breakdown
# (grams + per-ingredient macros), so the Recipes UI has something real to
# show/edit instead of "1 serving of <dish name>".
#
# Run with: bin/rails runner db/seed_recipe_ingredients.rb
#
# Quantities are grams; macros are for that quantity (not per 100g).
# Ingredient macros are approximate, standard values for common foods.
BREAKDOWNS = {
  "Paella" => [
    { name: "Rice", quantity: 150, kcal: 195, protein_g: 4.1, carbs_g: 42, fat_g: 0.5 },
    { name: "Chicken Thigh", quantity: 120, kcal: 216, protein_g: 24, carbs_g: 0, fat_g: 13 },
    { name: "Shrimp", quantity: 80, kcal: 79, protein_g: 19, carbs_g: 0.2, fat_g: 0.3 },
    { name: "Bell Peppers & Onion", quantity: 80, kcal: 37, protein_g: 1.1, carbs_g: 7.6, fat_g: 0.2 }
  ],
  "Vegan Protein Pasta Bolognese" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Plant-Based Ground", quantity: 100, kcal: 170, protein_g: 18, carbs_g: 6, fat_g: 8 },
    { name: "Tomato Sauce", quantity: 150, kcal: 48, protein_g: 2.3, carbs_g: 10.5, fat_g: 0.3 }
  ],
  "Buffalo-Style Chicken Bowl" => [
    { name: "Chicken Breast", quantity: 150, kcal: 248, protein_g: 46, carbs_g: 0, fat_g: 5 },
    { name: "Brown Rice (cooked)", quantity: 130, kcal: 144, protein_g: 3.4, carbs_g: 30, fat_g: 1.2 },
    { name: "Buffalo Sauce", quantity: 30, kcal: 10, protein_g: 0.1, carbs_g: 0.6, fat_g: 0.9 },
    { name: "Mixed Vegetables", quantity: 90, kcal: 58, protein_g: 2.5, carbs_g: 11.7, fat_g: 0.4 }
  ],
  "Roasted Potatoes with Chicken" => [
    { name: "Chicken Breast", quantity: 160, kcal: 264, protein_g: 49.6, carbs_g: 0, fat_g: 5.8 },
    { name: "Roasted Potatoes", quantity: 220, kcal: 328, protein_g: 5.5, carbs_g: 57.2, fat_g: 8.8 }
  ],
  "Cheese Spätzle with Chicken" => [
    { name: "Spätzle (cooked)", quantity: 220, kcal: 319, protein_g: 12.1, carbs_g: 59.4, fat_g: 4 },
    { name: "Chicken Breast", quantity: 130, kcal: 215, protein_g: 40.3, carbs_g: 0, fat_g: 4.7 },
    { name: "Cheddar Cheese", quantity: 40, kcal: 161, protein_g: 10, carbs_g: 0.5, fat_g: 13.2 }
  ],
  "Protein Pasta Alfredo" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Cream Sauce", quantity: 100, kcal: 195, protein_g: 2.5, carbs_g: 5, fat_g: 19 },
    { name: "Chicken Breast", quantity: 80, kcal: 132, protein_g: 24.8, carbs_g: 0, fat_g: 2.9 }
  ],
  "Protein Pasta with Salmon" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Salmon", quantity: 100, kcal: 208, protein_g: 20, carbs_g: 0, fat_g: 13 }
  ],
  "Chili con Carne" => [
    { name: "Ground Beef", quantity: 150, kcal: 375, protein_g: 39, carbs_g: 0, fat_g: 22.5 },
    { name: "Kidney Beans", quantity: 130, kcal: 165, protein_g: 11.3, carbs_g: 29.6, fat_g: 0.7 },
    { name: "Tomato Sauce", quantity: 130, kcal: 42, protein_g: 2, carbs_g: 9.1, fat_g: 0.3 },
    { name: "Spices", quantity: 10, kcal: 18, protein_g: 0.7, carbs_g: 3.3, fat_g: 0.5 }
  ],
  "Butter Chicken" => [
    { name: "Chicken Thigh", quantity: 200, kcal: 360, protein_g: 40, carbs_g: 0, fat_g: 21.6 },
    { name: "Curry Sauce", quantity: 180, kcal: 270, protein_g: 3.6, carbs_g: 10.8, fat_g: 23.4 },
    { name: "Rice (cooked)", quantity: 40, kcal: 52, protein_g: 1.1, carbs_g: 11.2, fat_g: 0.1 }
  ],
  "Chicken Fajita Bowl" => [
    { name: "Chicken Breast", quantity: 180, kcal: 297, protein_g: 55.8, carbs_g: 0, fat_g: 6.5 },
    { name: "Rice (cooked)", quantity: 150, kcal: 195, protein_g: 4.1, carbs_g: 42, fat_g: 0.5 },
    { name: "Bell Peppers & Onion", quantity: 100, kcal: 46, protein_g: 1.4, carbs_g: 9.5, fat_g: 0.3 }
  ],
  "Asian Style Noodles" => [
    { name: "Egg Noodles (cooked)", quantity: 220, kcal: 304, protein_g: 9.9, carbs_g: 55, fat_g: 4.6 },
    { name: "Chicken Breast", quantity: 100, kcal: 165, protein_g: 31, carbs_g: 0, fat_g: 3.6 },
    { name: "Mixed Vegetables", quantity: 80, kcal: 52, protein_g: 2.2, carbs_g: 10.4, fat_g: 0.3 }
  ],
  "Protein Pasta Bolognese" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Ground Beef", quantity: 110, kcal: 275, protein_g: 28.6, carbs_g: 0, fat_g: 16.5 },
    { name: "Tomato Sauce", quantity: 100, kcal: 32, protein_g: 1.5, carbs_g: 7, fat_g: 0.2 }
  ],
  "Pollock with Rice and Vegetables" => [
    { name: "Pollock", quantity: 180, kcal: 166, protein_g: 36, carbs_g: 0, fat_g: 1.8 },
    { name: "Rice (cooked)", quantity: 130, kcal: 169, protein_g: 3.5, carbs_g: 36.4, fat_g: 0.4 },
    { name: "Mixed Vegetables", quantity: 100, kcal: 65, protein_g: 2.8, carbs_g: 13, fat_g: 0.4 }
  ],
  "Red Thai Curry" => [
    { name: "Chicken Breast", quantity: 170, kcal: 281, protein_g: 52.7, carbs_g: 0, fat_g: 6.1 },
    { name: "Coconut Curry Sauce", quantity: 180, kcal: 234, protein_g: 3.4, carbs_g: 9.5, fat_g: 21.6 },
    { name: "Rice (cooked)", quantity: 70, kcal: 91, protein_g: 1.9, carbs_g: 19.6, fat_g: 0.2 }
  ],
  "Protein Pasta with Cream Cheese Sauce" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Cream Cheese Sauce", quantity: 110, kcal: 238, protein_g: 3.4, carbs_g: 15.4, fat_g: 13.5 }
  ],
  "Chicken, Rice and Broccoli" => [
    { name: "Chicken Breast", quantity: 180, kcal: 297, protein_g: 55.8, carbs_g: 0, fat_g: 6.5 },
    { name: "Rice (cooked)", quantity: 120, kcal: 156, protein_g: 3.2, carbs_g: 33.6, fat_g: 0.4 },
    { name: "Broccoli", quantity: 130, kcal: 46, protein_g: 3.6, carbs_g: 9.1, fat_g: 0.5 }
  ],
  "Sweet Potato Chicken Bowl" => [
    { name: "Chicken Breast", quantity: 160, kcal: 264, protein_g: 49.6, carbs_g: 0, fat_g: 5.8 },
    { name: "Sweet Potato (roasted)", quantity: 150, kcal: 135, protein_g: 3, carbs_g: 31.5, fat_g: 0.2 },
    { name: "Mixed Vegetables", quantity: 60, kcal: 39, protein_g: 1.7, carbs_g: 7.8, fat_g: 0.2 }
  ],
  "Thai Chicken Bowl" => [
    { name: "Chicken Breast", quantity: 180, kcal: 297, protein_g: 55.8, carbs_g: 0, fat_g: 6.5 },
    { name: "Mixed Vegetables", quantity: 120, kcal: 78, protein_g: 3.4, carbs_g: 15.6, fat_g: 0.5 },
    { name: "Peanut Sauce", quantity: 20, kcal: 58, protein_g: 2, carbs_g: 3, fat_g: 4.5 }
  ],
  "Protein Pizza Margherita" => [
    { name: "Protein Pizza Dough", quantity: 220, kcal: 511, protein_g: 33, carbs_g: 82, fat_g: 6.6 },
    { name: "Tomato Sauce", quantity: 80, kcal: 26, protein_g: 1.2, carbs_g: 5.6, fat_g: 0.2 },
    { name: "Mozzarella", quantity: 90, kcal: 252, protein_g: 25.2, carbs_g: 2.7, fat_g: 15.3 }
  ],
  "Protein Pizza Chicken & Peppers" => [
    { name: "Protein Pizza Dough", quantity: 240, kcal: 557, protein_g: 36, carbs_g: 89.5, fat_g: 7.2 },
    { name: "Chicken Breast", quantity: 100, kcal: 165, protein_g: 31, carbs_g: 0, fat_g: 3.6 },
    { name: "Mozzarella", quantity: 80, kcal: 224, protein_g: 22.4, carbs_g: 2.4, fat_g: 13.6 },
    { name: "Bell Peppers", quantity: 60, kcal: 19, protein_g: 0.6, carbs_g: 3.6, fat_g: 0.2 }
  ],
  "Tikka Masala" => [
    { name: "Chicken Thigh", quantity: 200, kcal: 360, protein_g: 40, carbs_g: 0, fat_g: 21.6 },
    { name: "Tikka Masala Sauce", quantity: 200, kcal: 240, protein_g: 4, carbs_g: 16, fat_g: 16 },
    { name: "Rice (cooked)", quantity: 40, kcal: 52, protein_g: 1.1, carbs_g: 11.2, fat_g: 0.1 }
  ],
  "Protein Penne with Veggie Bolognese" => [
    { name: "Protein Pasta (cooked)", quantity: 220, kcal: 352, protein_g: 28.6, carbs_g: 53, fat_g: 5.5 },
    { name: "Plant-Based Ground", quantity: 90, kcal: 153, protein_g: 16.2, carbs_g: 5.4, fat_g: 7.2 },
    { name: "Tomato Sauce", quantity: 110, kcal: 35, protein_g: 1.7, carbs_g: 7.7, fat_g: 0.2 }
  ],
  "Asian Noodles with Beef" => [
    { name: "Egg Noodles (cooked)", quantity: 220, kcal: 304, protein_g: 9.9, carbs_g: 55, fat_g: 4.6 },
    { name: "Beef Strips", quantity: 130, kcal: 260, protein_g: 32.5, carbs_g: 0, fat_g: 14.3 },
    { name: "Mixed Vegetables", quantity: 60, kcal: 39, protein_g: 1.7, carbs_g: 7.8, fat_g: 0.2 }
  ],
  "Philly Cheese & Beef Bowl" => [
    { name: "Beef Strips", quantity: 170, kcal: 340, protein_g: 42.5, carbs_g: 0, fat_g: 18.7 },
    { name: "Bell Peppers & Onion", quantity: 100, kcal: 46, protein_g: 1.4, carbs_g: 9.5, fat_g: 0.3 },
    { name: "Cheddar Cheese", quantity: 40, kcal: 161, protein_g: 10, carbs_g: 0.5, fat_g: 13.2 }
  ],
  "Chicken Döner-Style" => [
    { name: "Chicken Thigh", quantity: 180, kcal: 324, protein_g: 36, carbs_g: 0, fat_g: 19.4 },
    { name: "Tortilla Wrap", quantity: 90, kcal: 196, protein_g: 5.4, carbs_g: 32.4, fat_g: 4.9 },
    { name: "Mixed Vegetables & Sauce", quantity: 100, kcal: 77, protein_g: 4.6, carbs_g: 23.6, fat_g: 0.7 }
  ],
  "Linguine Aglio e Olio" => [
    { name: "Pasta (cooked)", quantity: 280, kcal: 367, protein_g: 14, carbs_g: 70, fat_g: 3.1 },
    { name: "Olive Oil", quantity: 30, kcal: 265, protein_g: 0, carbs_g: 0, fat_g: 30 },
    { name: "Chicken Breast", quantity: 35, kcal: 58, protein_g: 10.9, carbs_g: 0, fat_g: 1.3 }
  ],
  "Gnocchi with Salmon" => [
    { name: "Gnocchi (cooked)", quantity: 280, kcal: 420, protein_g: 9.8, carbs_g: 86.8, fat_g: 2 },
    { name: "Salmon", quantity: 110, kcal: 229, protein_g: 22, carbs_g: 0, fat_g: 14.3 },
    { name: "Cream Sauce", quantity: 20, kcal: 39, protein_g: 0.5, carbs_g: 1, fat_g: 3.8 }
  ],
  "Rice Noodles in Coconut Sauce" => [
    { name: "Rice Noodles (cooked)", quantity: 250, kcal: 273, protein_g: 4.5, carbs_g: 62.5, fat_g: 0.5 },
    { name: "Chicken Breast", quantity: 150, kcal: 248, protein_g: 46, carbs_g: 0, fat_g: 5 },
    { name: "Coconut Curry Sauce", quantity: 65, kcal: 85, protein_g: 1.2, carbs_g: 3.4, fat_g: 7.8 }
  ],
  "Lasagne" => [
    { name: "Lasagne Sheets (cooked)", quantity: 150, kcal: 222, protein_g: 8.1, carbs_g: 43.5, fat_g: 1.4 },
    { name: "Ground Beef", quantity: 130, kcal: 325, protein_g: 33.8, carbs_g: 0, fat_g: 19.5 },
    { name: "Tomato Sauce", quantity: 100, kcal: 32, protein_g: 1.5, carbs_g: 7, fat_g: 0.2 },
    { name: "Mozzarella", quantity: 30, kcal: 84, protein_g: 8.4, carbs_g: 0.9, fat_g: 5.1 }
  ],
  "Vegetable Lasagne" => [
    { name: "Lasagne Sheets (cooked)", quantity: 170, kcal: 252, protein_g: 9.2, carbs_g: 49.3, fat_g: 1.6 },
    { name: "Mixed Vegetables", quantity: 200, kcal: 130, protein_g: 5.6, carbs_g: 26, fat_g: 0.8 },
    { name: "Cheddar Cheese", quantity: 65, kcal: 261, protein_g: 16.3, carbs_g: 0.8, fat_g: 21.5 }
  ],
  "Burrito Bowl" => [
    { name: "Chicken Breast", quantity: 160, kcal: 264, protein_g: 49.6, carbs_g: 0, fat_g: 5.8 },
    { name: "Rice (cooked)", quantity: 150, kcal: 195, protein_g: 4.1, carbs_g: 42, fat_g: 0.5 },
    { name: "Kidney Beans", quantity: 100, kcal: 127, protein_g: 8.7, carbs_g: 22.8, fat_g: 0.5 },
    { name: "Cheddar Cheese", quantity: 25, kcal: 100, protein_g: 6.3, carbs_g: 0.3, fat_g: 8.3 }
  ],
  "Mac & Cheese with Chicken" => [
    { name: "Pasta (cooked)", quantity: 220, kcal: 288, protein_g: 11, carbs_g: 55, fat_g: 2.4 },
    { name: "Cheddar Cheese Sauce", quantity: 150, kcal: 315, protein_g: 15, carbs_g: 6, fat_g: 25.5 },
    { name: "Chicken Breast", quantity: 130, kcal: 215, protein_g: 40.3, carbs_g: 0, fat_g: 4.7 }
  ],
  "Salmon with Pumpkin Purée" => [
    { name: "Salmon", quantity: 250, kcal: 520, protein_g: 50, carbs_g: 0, fat_g: 32.5 },
    { name: "Pumpkin Purée", quantity: 250, kcal: 85, protein_g: 3.3, carbs_g: 21.3, fat_g: 0.3 },
    { name: "Olive Oil", quantity: 13, kcal: 115, protein_g: 0, carbs_g: 0, fat_g: 13 }
  ],
  "Vegan Green Curry" => [
    { name: "Tofu", quantity: 200, kcal: 152, protein_g: 16, carbs_g: 3.8, fat_g: 9.6 },
    { name: "Coconut Curry Sauce", quantity: 250, kcal: 325, protein_g: 4.75, carbs_g: 13.25, fat_g: 30 },
    { name: "Rice (cooked)", quantity: 145, kcal: 189, protein_g: 3.9, carbs_g: 40.6, fat_g: 0.4 }
  ],
  "Chicken with Hummus" => [
    { name: "Chicken Breast", quantity: 220, kcal: 363, protein_g: 68.2, carbs_g: 0, fat_g: 7.9 },
    { name: "Hummus", quantity: 180, kcal: 299, protein_g: 14.4, carbs_g: 25.2, fat_g: 18 },
    { name: "Mixed Vegetables", quantity: 90, kcal: 59, protein_g: 2.5, carbs_g: 11.7, fat_g: 0.4 }
  ],
  "Cheeseburger Bowl" => [
    { name: "Ground Beef", quantity: 170, kcal: 425, protein_g: 44.2, carbs_g: 0, fat_g: 25.5 },
    { name: "Cheddar Cheese", quantity: 30, kcal: 121, protein_g: 7.5, carbs_g: 0.4, fat_g: 9.9 },
    { name: "Mixed Vegetables", quantity: 130, kcal: 45, protein_g: 2.6, carbs_g: 8.6, fat_g: 0.4 }
  ],
  "Chickpea Masala" => [
    { name: "Chickpeas (cooked)", quantity: 220, kcal: 361, protein_g: 19.6, carbs_g: 59.4, fat_g: 5.7 },
    { name: "Tomato Sauce", quantity: 130, kcal: 42, protein_g: 2, carbs_g: 9.1, fat_g: 0.3 }
  ],
  "Vegan Biryani" => [
    { name: "Rice (cooked)", quantity: 350, kcal: 455, protein_g: 9.5, carbs_g: 98, fat_g: 1.1 },
    { name: "Mixed Vegetables", quantity: 150, kcal: 98, protein_g: 4.2, carbs_g: 19.5, fat_g: 0.6 },
    { name: "Chickpeas (cooked)", quantity: 25, kcal: 41, protein_g: 2.2, carbs_g: 6.8, fat_g: 0.7 }
  ],
  "Rice Flour Crêpes" => [
    { name: "Rice Flour", quantity: 100, kcal: 350, protein_g: 7.2, carbs_g: 78.5, fat_g: 0.6 },
    { name: "Eggs", quantity: 150, kcal: 233, protein_g: 19.5, carbs_g: 1.7, fat_g: 16.5 }
  ]
}.freeze

BREAKDOWNS.each do |recipe_name, ingredients|
  recipe = Recipe.find_by(name: recipe_name)

  unless recipe
    puts "SKIP (not found): #{recipe_name}"
    next
  end

  recipe.recipe_ingredients.destroy_all
  ingredients.each { |attrs| recipe.recipe_ingredients.create!(attrs) }
  puts "Updated #{recipe_name}: #{ingredients.size} ingredients, #{recipe.reload.total_kcal.to_i} kcal"
end
