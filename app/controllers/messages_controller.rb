class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat

  def create
    @message = @chat.messages.new(message_params)
    @message.role = "user"

    if @message.save
      ruby_llm_chat = RubyLLM.chat(model: "gpt-4o-mini")

      build_conversation_history(ruby_llm_chat)

      response = ruby_llm_chat
        .with_instructions(instructions)
        .ask(@message.content)

      @chat.messages.create!(role: "assistant", content: response.content)

      redirect_to chat_path(@chat)
    else
      render "chats/show", status: :unprocessable_entity
    end
  end

  private

  def set_chat
    @chat = current_user.chats.find(params[:chat_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def build_conversation_history(ruby_llm_chat)
    @chat.messages.each do |message|
      ruby_llm_chat.add_message(
        role: message.role,
        content: message.content
      )
    end
  end

  def instructions
    <<~PROMPT
      You are MacroChef, an expert nutrition assistant.

      Help the user refine their meal plan based on the existing conversation.
      Keep context from previous messages.
      Respect allergies, diet, calorie targets and macros.
      Answer in Markdown.
    PROMPT
  end
end
