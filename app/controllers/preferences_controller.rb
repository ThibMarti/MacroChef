class PreferencesController < ApplicationController
  before_action :authenticate_user!

  def new
    @preference = Preference.new
  end

  def create
    @preference = Preference.new(preference_params)
    @preference.user = current_user

    if @preference.save
      @chat = Chat.create!(user: current_user, preference: @preference)

      user_prompt = @preference.content

      ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")

      response = ruby_llm_chat
                 .with_instructions(system_prompt)
                 .ask(user_prompt)

      @chat.messages.create!(role: "user", content: user_prompt)
      @chat.messages.create!(role: "assistant", content: response.content)

      redirect_to chat_path(@chat)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def preference_params
    params.require(:preference).permit(:content)
  end

  def system_prompt
    <<~PROMPT
      You are MacroChef, an expert nutrition assistant.

      Your job is to create practical meal plans based on the user's dietary preferences, calorie target, macros, allergies and goals.

      Always:
      - Respect the user's constraints.
      - Structure the answer clearly.
      - Include meals, ingredients and approximate calories/macros.
      - Keep the answer realistic and easy to cook.
      - Answer in Markdown.
    PROMPT
  end
end
