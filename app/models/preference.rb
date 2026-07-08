class Preference < ApplicationRecord
  belongs_to :user
  has_many :chats, dependent: :destroy

  validates :content, presence: true
end
