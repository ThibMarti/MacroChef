class ChatsController < ApplicationController
  def show
    @chat = current_user.chats.find(params[:id])
  end
end
