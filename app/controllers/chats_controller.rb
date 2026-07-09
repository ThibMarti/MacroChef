class ChatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @chats = current_user.chats.includes(:messages).order(created_at: :desc)
  end

  def show
    @chat = current_user.chats.find(params[:id])
    @message = Message.new
  end
end
