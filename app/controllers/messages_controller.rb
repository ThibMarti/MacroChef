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
