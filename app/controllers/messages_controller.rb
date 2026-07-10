class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat

  def create
    @message = @chat.messages.new(message_params)
    @message.role = "user"

    if @message.save
      respond_to_assistant_reply
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "new_message_container",
            partial: "messages/form",
            locals: { chat: @chat, message: @message }
          )
        end

        format.html { render "chats/show", status: :unprocessable_entity }
      end
    end
  end

  # Replaces one meal (identified by day_index/meal_index within the plan
  # JSON stored on this message) with a different Recipe. Keeps the same
  # kcal budget that slot already had (its current "kcal" IS its day-target
  # share, by construction — see MealPlanMacros), so swapping a dish never
  # knocks the day's total off target.
  def swap_meal
    message = @chat.messages.find(params[:id])
    recipe = Recipe.find(params[:recipe_id])

    parsed = JSON.parse(message.content)
    day = parsed.dig("week", params[:day_index].to_i)
    meal = day && day["meals"]&.at(params[:meal_index].to_i)

    if meal
      share_kcal = meal["kcal"].to_f
      share_kcal = recipe.total_kcal.to_f if share_kcal <= 0
      MealPlanMacros.apply_recipe!(meal, recipe, share_kcal)
      message.update!(content: JSON.generate(parsed))
    end

    redirect_to chat_path(@chat, open_day: params[:day_index])
  rescue JSON::ParserError, ActiveRecord::RecordNotFound
    redirect_to chat_path(@chat), alert: "Couldn't swap that meal."
  end

  # Overrides one ingredient's portion size (grams) within one specific meal
  # instance — e.g. "150g rice" -> "200g rice" for just this Tuesday dinner,
  # without touching the Recipe itself. Recomputes and persists that
  # ingredient's kcal/protein/carbs/fat immediately (see
  # MealPlanMacros.set_ingredient_quantity!) rather than only storing the new
  # quantity, so the change shows up right away even for ingredients whose
  # name doesn't exactly match the recipe's (older plans the LLM generated
  # before names were standardized).
  def update_ingredient
    message = @chat.messages.find(params[:id])

    parsed = JSON.parse(message.content)
    day = parsed.dig("week", params[:day_index].to_i)
    meal = day && day["meals"]&.at(params[:meal_index].to_i)
    ingredient = meal && meal["ingredients"]&.at(params[:ingredient_index].to_i)

    if ingredient
      recipe = Recipe.find_by(name: meal["name"])
      MealPlanMacros.set_ingredient_quantity!(ingredient, recipe, params[:quantity].to_f)
      message.update!(content: JSON.generate(parsed))
    end

    redirect_to chat_path(@chat, open_day: params[:day_index])
  rescue JSON::ParserError
    redirect_to chat_path(@chat), alert: "Couldn't update that ingredient."
  end

  # Adds a new ingredient row to one specific meal instance, using an
  # existing ingredient's per-gram macro rate (looked up by name from
  # RecipeIngredient, wherever it's defined) scaled to the chosen quantity.
  # Only affects this meal — it doesn't touch the underlying Recipe.
  def add_ingredient
    message = @chat.messages.find(params[:id])
    reference = RecipeIngredient.find_by(name: params[:ingredient_name])

    parsed = JSON.parse(message.content)
    day = parsed.dig("week", params[:day_index].to_i)
    meal = day && day["meals"]&.at(params[:meal_index].to_i)

    if meal && reference && reference.quantity.to_f.positive?
      quantity = params[:quantity].to_f
      rate = ->(attr) { reference.public_send(attr).to_f / reference.quantity.to_f }

      meal["ingredients"] ||= []
      meal["ingredients"] << {
        "name" => reference.name,
        "quantity" => quantity.round,
        "unit" => "g",
        "kcal" => (rate.call(:kcal) * quantity).round,
        "protein_g" => (rate.call(:protein_g) * quantity).round(1),
        "carbs_g" => (rate.call(:carbs_g) * quantity).round(1),
        "fat_g" => (rate.call(:fat_g) * quantity).round(1)
      }

      message.update!(content: JSON.generate(parsed))
    end

    redirect_to chat_path(@chat, open_day: params[:day_index])
  rescue JSON::ParserError
    redirect_to chat_path(@chat), alert: "Couldn't add that ingredient."
  end

  # Removes one ingredient row from one specific meal instance. Only affects
  # this meal — it doesn't touch the underlying Recipe.
  def remove_ingredient
    message = @chat.messages.find(params[:id])

    parsed = JSON.parse(message.content)
    day = parsed.dig("week", params[:day_index].to_i)
    meal = day && day["meals"]&.at(params[:meal_index].to_i)
    ingredient_index = params[:ingredient_index].to_i

    if meal && meal["ingredients"] && meal["ingredients"][ingredient_index]
      meal["ingredients"].delete_at(ingredient_index)
      message.update!(content: JSON.generate(parsed))
    end

    redirect_to chat_path(@chat, open_day: params[:day_index])
  rescue JSON::ParserError
    redirect_to chat_path(@chat), alert: "Couldn't remove that ingredient."
  end

  private

  def set_chat
    @chat = current_user.chats.find(params[:chat_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def respond_to_assistant_reply
    @assistant_message = @chat.messages.create!(role: "assistant", content: "")

    response = ask_llm
    @assistant_message.update!(content: response.content)
    @assistant_message.broadcast_replace_to_chat

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to chat_path(@chat) }
    end
  end

  def ask_llm
    ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")
    build_conversation_history(ruby_llm_chat)
    ruby_llm_chat.with_tool(SearchRecipesTool)
    ruby_llm_chat.with_instructions(instructions)
    @ruby_llm_chat.ask(@message.content) do |chunk|
      next if chunk.content.blank? # skip empty chunks

      @assistant_message.content += chunk.content
      broadcast_replace(@assistant_message)
    end
  end

  def build_conversation_history(ruby_llm_chat)
    @chat.messages.each do |message|
      ruby_llm_chat.add_message(
        role: message.role,
        content: message.content
      )
      next if message.content.blank?

      @ruby_llm_chat.add_message(message)
    end
  end

  def broadcast_replace(message)
    Turbo::StreamsChannel.broadcast_replace_to(@chat, target: helpers.dom_id(message), partial: "messages/message",
                                                      locals: { message: message })
  end

  def instructions
    <<~PROMPT
      You are MacroChef, an expert nutrition assistant.

      Help the user refine their meal plan based on the existing conversation.
      Keep context from previous messages.
      Respect allergies, diet, calorie targets and macros.
      Use the search_recipes tool to look up exact macros for catalog dishes
      instead of guessing them from memory.
      Answer in Markdown.
    PROMPT
  end
end
