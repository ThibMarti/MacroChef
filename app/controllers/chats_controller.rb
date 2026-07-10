class ChatsController < ApplicationController
  before_action :authenticate_user!

  # "My Meal Plans" just jumps straight to the most recent plan's full view
  # (macros, days, shopping list, everything) instead of a list to click
  # through — only falls back to an empty-state page if none exists yet.
  def index
    latest_chat = current_user.chats.order(created_at: :desc).first
    redirect_to chat_path(latest_chat) if latest_chat
  end

  def show
    @chat = current_user.chats.find(params[:id])
    @message = Message.new
  end
end
