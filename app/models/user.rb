# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  # Associations
  has_many :chats, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :summaries, dependent: :destroy
  has_many :messages, foreign_key: :sender_id, dependent: :destroy  # RDB版メッセージとの関連（送信者として）

  # Validations
  validates :name, presence: true, length: { maximum: AppConstants::MAX_NAME_LENGTH }
  validates :email, presence: true,
                    length: { maximum: AppConstants::MAX_EMAIL_LENGTH },
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: AppConstants::MIN_PASSWORD_LENGTH }, allow_nil: true
  validates :is_active, inclusion: { in: [ true, false ] }

  # Callbacks
  before_save :downcase_email

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }

  # Instance Methods
  def deactivate!
    update!(is_active: false)
  end

  def activate!
    update!(is_active: true)
  end

  private

  def downcase_email
    self.email = email.downcase
  end
end
