# frozen_string_literal: true

class Chat < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :tag, optional: true
  has_many :summaries, dependent: :destroy
  has_many :messages, dependent: :destroy  # RDB版メッセージとの関連

  # Validations
  validates :title, length: { maximum: 120 }, allow_blank: true
  validates :user, presence: true

  # Callbacks
  before_create :generate_default_title

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_tag, ->(tag_id) { where(tag_id: tag_id) }
  scope :without_tag, -> { where(tag_id: nil) }
  scope :with_tag, -> { where.not(tag_id: nil) }
  scope :by_date_range, ->(start_date, end_date) {
    where(created_at: start_date..end_date)
  }

  # Instance Methods
  def chat_uid
    "chat-#{id}"
  end

  # メッセージ関連メソッド（RDB版）
  def messages_count
    messages.count
  end

  def latest_message
    messages.order(sent_at: :desc).first
  end

  # MongoDB連携用メソッド（将来的な移行用に保持）
  # def messages_doc_count
  #   MessagesDoc.where(chat_uid: chat_uid).count
  # end
  #
  # def latest_message_doc
  #   MessagesDoc.where(chat_uid: chat_uid).order(send_at: :desc).first
  # end

  def has_summary?
    summaries.where(period: "session").exists?
  end

  def session_summary
    summaries.find_by(period: "session")
  end

  private

  def generate_default_title
    self.title ||= "チャット #{Time.current.strftime('%Y年%m月%d日 %H:%M')}"
  end
end
