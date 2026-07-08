class Message < ApplicationRecord
  MAX_USER_MESSAGES = 10

  belongs_to :chat

  validates :role, presence: true
  validates :content, presence: true
  validate :user_message_limit, if: -> { role == "user" }

  private

  def user_message_limit
    if chat.messages.where(role: "user").count >= MAX_USER_MESSAGES
      errors.add(:content, "You can only send #{MAX_USER_MESSAGES} messages per chat.")
    end
  end
end
