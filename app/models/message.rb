class Message < ApplicationRecord
  MAX_USER_MESSAGES = 10

  belongs_to :chat

  validates :role, presence: true
  validates :content, presence: true, unless: -> { role == "assistant" }
  validate :user_message_limit, if: -> { role == "user" }

  after_create_commit :broadcast_append_to_chat

  def broadcast_replace_to_chat
    broadcast_replace_to chat, target: self, partial: "messages/message", locals: { message: self }
  end

  private

  def broadcast_append_to_chat
    broadcast_append_to chat, target: "messages", partial: "messages/message", locals: { message: self }
  end

  def user_message_limit
    return unless chat.messages.where(role: "user").count >= MAX_USER_MESSAGES

    errors.add(:content, "You can only send #{MAX_USER_MESSAGES} messages per chat.")
  end
end
