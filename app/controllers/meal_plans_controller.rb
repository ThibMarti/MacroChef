class MealPlansController < ApplicationController
  def index
    @chats = current_user.chats.order(created_at: :desc)
  end
end
