class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :home

  def home
    if user_signed_in?
      @chats = current_user.chats.includes(:messages).order(created_at: :desc).to_a
      @recent_chats = @chats.first(3)
    end
  end
end
