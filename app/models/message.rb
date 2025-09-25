# ==============================================================================
# RDB版 Message モデル (ActiveRecord)
# インスタンススペック制約のため、MongoDBではなくRDBを使用
# ==============================================================================
class Message < ApplicationRecord
  # Constants for sender_kind
  SENDER_USER = "USER".freeze
  SENDER_ASSISTANT = "ASSISTANT".freeze
  SENDER_KINDS = [ SENDER_USER, SENDER_ASSISTANT ].freeze

  # Associations (based on DB_GUID_RDB_MESSAGES.md)
  belongs_to :chat
  belongs_to :sender, class_name: "User", foreign_key: "sender_id"

  # Validations
  validates :chat_id, presence: true
  validates :sender_id, presence: true
  validates :content, presence: true, length: { maximum: 10_000 }
  validates :sent_at, presence: true
  validates :sender_kind, presence: true, inclusion: { in: SENDER_KINDS }
  validates :emotion_score, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 1
  }, allow_nil: true

  # Custom validation for emotion_keywords JSON array
  validate :emotion_keywords_size_limit

  # Callbacks
  before_validation :set_sent_at
  before_save :normalize_emotion_keywords

  # Scopes
  scope :by_chat, ->(chat_id) { where(chat_id: chat_id) }
  scope :by_sender, ->(sender_id) { where(sender_id: sender_id) }
  scope :recent_first, -> { order(sent_at: :desc) }
  scope :chronological, -> { order(sent_at: :asc) }
  scope :with_emotion, -> { where.not(emotion_score: nil) }
  scope :from_user, -> { where(sender_kind: SENDER_USER) }
  scope :from_assistant, -> { where(sender_kind: SENDER_ASSISTANT) }

  # Class methods
  def self.for_chat(chat_id)
    by_chat(chat_id).chronological
  end

  def self.create_user_message(chat_id:, sender_id:, content:, **attrs)
    create!(
      chat_id: chat_id,
      sender_id: sender_id,
      content: content,
      sender_kind: SENDER_USER,
      **attrs
    )
  end

  def self.create_ai_message(chat_id:, content:, llm_metadata: {}, **attrs)
    chat = Chat.find(chat_id)
    create!(
      chat_id: chat_id,
      sender_id: chat.user_id,  # AIメッセージでも関連ユーザーIDを保存
      content: content,
      llm_metadata: llm_metadata,
      sender_kind: SENDER_ASSISTANT,
      **attrs
    )
  end

  def self.create_system_message(chat_id:, content:, **attrs)
    chat = Chat.find(chat_id)
    create!(
      chat_id: chat_id,
      sender_id: chat.user_id,  # システムメッセージでも関連ユーザーIDを保存
      content: content,
      sender_kind: SENDER_ASSISTANT,  # システムメッセージもASSISTANT扱い
      **attrs
    )
  end

  # Instance methods
  # メッセージ種別の判定（sender_kindベース）
  def from_user?
    sender_kind == SENDER_USER
  end

  def from_assistant?
    sender_kind == SENDER_ASSISTANT
  end

  # 旧メソッド（後方互換性のため残す）
  def user_message?
    from_user?
  end

  def ai_message?
    from_assistant?
  end

  # emotion_keywordsのヘルパーメソッド（JSON配列として扱う）
  def add_emotion_keyword(keyword)
    self.emotion_keywords ||= []
    self.emotion_keywords << keyword unless emotion_keywords.include?(keyword)
  end

  def remove_emotion_keyword(keyword)
    return unless emotion_keywords.is_a?(Array)
    self.emotion_keywords.delete(keyword)
  end

  def emotion_keywords_list
    emotion_keywords.is_a?(Array) ? emotion_keywords : []
  end

  private

  def emotion_keywords_size_limit
    if emotion_keywords.present? && emotion_keywords.is_a?(Array) && emotion_keywords.size > 10
      errors.add(:emotion_keywords, "は10個まで登録可能です")
    end
  end

  def set_sent_at
    self.sent_at ||= Time.current
  end

  def normalize_emotion_keywords
    # 確実に配列として保存
    if emotion_keywords.present? && !emotion_keywords.is_a?(Array)
      self.emotion_keywords = [ emotion_keywords ].flatten.compact
    end
  end
end

# ==============================================================================
# MongoDB版 Message モデル (Mongoid) - 既存実装として保持
# 将来的な移行やスケーリング時のために残しておく
# 現在は使用していません
# ==============================================================================
# class MessageDoc
#   include Mongoid::Document
#   include Mongoid::Timestamps
#
#   # MongoDB Collection name
#   store_in collection: "messages_doc"
#
#   # Fields based on DB_GUID.md specification
#   field :chat_uid, type: String
#   field :sender_id, type: Integer
#   field :content, type: String
#   field :llm_metadata, type: Hash, default: {}
#   field :emotion_score, type: Float
#   field :emotion_keywords, type: Array, default: []
#   field :send_at, type: Time
#
#   # Validations
#   validates :chat_uid, presence: true
#   validates :sender_id, presence: true
#   validates :content, presence: true, length: { maximum: 10_000 }
#   validates :send_at, presence: true
#   validates :emotion_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
#
#   # Custom validation for emotion_keywords array size
#   validate :emotion_keywords_size_limit
#
#   # Indexes for performance
#   index({ chat_uid: 1, send_at: -1 })
#   index({ sender_id: 1 })
#   index({ send_at: -1 })
#
#   # Scopes
#   scope :by_chat, ->(chat_uid) { where(chat_uid: chat_uid) }
#   scope :by_sender, ->(sender_id) { where(sender_id: sender_id) }
#   scope :recent_first, -> { order(send_at: :desc) }
#   scope :chronological, -> { order(send_at: :asc) }
#
#   # Class methods
#   def self.for_chat(chat_id)
#     chat_uid = "chat-#{chat_id}"
#     by_chat(chat_uid).chronological
#   end
#
#   # Instance methods
#   def chat_id
#     chat_uid&.gsub(/^chat-/, '')&.to_i
#   end
#
#   def user_message?
#     sender_id.present? && sender_id > 0
#   end
#
#   def system_message?
#     !user_message?
#   end
#
#   # Before validation callback to ensure send_at is set
#   before_validation :set_send_at
#
#   private
#
#   def emotion_keywords_size_limit
#     if emotion_keywords.present? && emotion_keywords.size > 10
#       errors.add(:emotion_keywords, "は10個まで登録可能です")
#     end
#   end
#
#   def set_send_at
#     self.send_at ||= Time.current
#   end
# end
