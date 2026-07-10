class RecipesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_recipe, only: [:show, :edit, :update, :toggle_favorite]

  def index
    @favorite_recipe_ids = current_user.favorites.pluck(:recipe_id).to_set
    @favorites_only = params[:favorites].present?

    @recipes = Recipe.includes(:recipe_ingredients, photo_attachment: :blob).ordered
    @recipes = @recipes.where(id: @favorite_recipe_ids) if @favorites_only
  end

  def show
    @is_favorite = @recipe.favorited_by?(current_user)
  end

  def new
  end

  # Generates a new Recipe (name, category, structured ingredients) from a
  # one-line natural-language description via the LLM, e.g. "sweet potato
  # fries, fry sauce and salmon". The generated recipe is a normal, editable
  # Recipe row like any other — same schema, same nested-ingredient edit form
  # — so the user reviews/adjusts it on the edit page right after.
  def create
    description = params[:description].to_s.strip

    if description.blank?
      redirect_to new_recipe_path, alert: "Describe the dish you want first."
      return
    end

    ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
    response = ruby_llm_chat.with_instructions(generator_prompt).ask(description)
    parsed = JSON.parse(response.content)

    recipe = Recipe.new(
      name: parsed["name"].to_s.strip,
      category: Recipe::CATEGORIES.include?(parsed["category"]) ? parsed["category"] : "main"
    )

    Array(parsed["ingredients"]).each do |ingredient|
      recipe.recipe_ingredients.build(
        name: ingredient["name"],
        quantity: ingredient["quantity_g"],
        kcal: ingredient["kcal"],
        protein_g: ingredient["protein_g"],
        carbs_g: ingredient["carbs_g"],
        fat_g: ingredient["fat_g"]
      )
    end

    if recipe.save
      redirect_to edit_recipe_path(recipe), notice: "Recipe generated — review and adjust it below."
    else
      redirect_to new_recipe_path, alert: recipe.errors.full_messages.to_sentence
    end
  rescue JSON::ParserError
    redirect_to new_recipe_path, alert: "Couldn't generate that recipe — try describing it differently."
  end

  def edit
    3.times { @recipe.recipe_ingredients.build }
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: "Recipe updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle_favorite
    favorite = current_user.favorites.find_by(recipe: @recipe)

    if favorite
      favorite.destroy
    else
      current_user.favorites.create!(recipe: @recipe)
    end

    redirect_back fallback_location: recipe_path(@recipe)
  end

  private

  def set_recipe
    @recipe = Recipe.find(params[:id])
  end

  def recipe_params
    params.require(:recipe).permit(
      :name, :category, :photo,
      recipe_ingredients_attributes: [:id, :name, :quantity, :kcal, :protein_g, :carbs_g, :fat_g, :_destroy]
    )
  end

  def generator_prompt
    <<~PROMPT
      You are MacroChef's recipe generator. The user describes a dish in one short message
      (e.g. "sweet potato fries, fry sauce and salmon"). Build a complete, realistic recipe from
      it and output ONLY a JSON object — no prose, no markdown, no code fences — with this exact
      schema:

      {
        "name": "Sweet Potato Fries with Fry Sauce and Salmon",
        "category": "main",
        "ingredients": [
          { "name": "Sweet Potato", "quantity_g": 250, "kcal": 215, "protein_g": 4.5, "carbs_g": 50, "fat_g": 0.3 },
          { "name": "Salmon", "quantity_g": 180, "kcal": 374, "protein_g": 36, "carbs_g": 0, "fat_g": 23.4 },
          { "name": "Fry Sauce", "quantity_g": 40, "kcal": 150, "protein_g": 0.5, "carbs_g": 4, "fat_g": 15 }
        ]
      }

      Rules:
      - "category" must be exactly one of: "main" (lunch/dinner dish), "breakfast", or "snack" —
        infer it from the dish described.
      - Break the dish into 2-6 realistic ingredients with plausible gram quantities for one
        serving, using standard, well-known nutrition values (kcal/protein_g/carbs_g/fat_g) for
        the quantity given — not per 100g, for that exact quantity.
      - Each ingredient's kcal must be internally consistent with its own macros: kcal ≈
        protein_g*4 + carbs_g*4 + fat_g*9 (within ~5%).
      - "name" for the recipe should be a clean, appetizing title-case dish name (not a copy of
        the user's raw wording).
      - Do not invent brand names or reference any commercial product.
    PROMPT
  end
end
