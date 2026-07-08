class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :home

  def home
    @chats = current_user.chats.order(created_at: :desc) if user_signed_in?
  end
end
