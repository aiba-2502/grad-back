# frozen_string_literal: true

class Tag < ApplicationRecord
  # Associations
  has_many :chats, dependent: :nullify

  # Validations
  validates :name, presence: true,
                   length: { maximum: 50 },
                   uniqueness: { case_sensitive: false }
  validates :category, length: { maximum: 30 }, allow_blank: true

  # Callbacks
  before_save :normalize_name

  # Scopes
  scope :by_category, ->(category) { where(category: category) }
  scope :emotion_tags, -> { where(category: "emotion") }
  scope :topic_tags, -> { where(category: "topic") }
  scope :value_tags, -> { where(category: "value") }
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }

  # Class Methods
  def self.categories
    {
      topic: "topic",      # 話題系タグ
      emotion: "emotion",  # 感情系タグ
      value: "value"       # 価値観軸タグ
    }
  end

  # Instance Methods
  def emotion_tag?
    category == "emotion"
  end

  def topic_tag?
    category == "topic"
  end

  def value_tag?
    category == "value"
  end

  private

  def normalize_name
    self.name = name.strip.downcase if name.present?
  end
end
