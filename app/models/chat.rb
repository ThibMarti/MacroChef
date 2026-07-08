class Chat < ApplicationRecord
  belongs_to :user
  belongs_to :preference
  has_many :messages, dependent: :destroy
end
