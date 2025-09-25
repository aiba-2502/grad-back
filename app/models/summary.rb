# frozen_string_literal: true

class Summary < ApplicationRecord
  # Enums
  enum :period, {
    session: "session",
    daily: "daily",
    weekly: "weekly",
    monthly: "monthly"
  }, validate: true

  # Associations
  belongs_to :user, optional: true
  belongs_to :chat, optional: true

  # Validations
  validates :period, presence: true
  validates :tally_start_at, presence: true
  validates :tally_end_at, presence: true
  validates :analysis_data, presence: true

  # Conditional validations based on period
  validates :chat_id, presence: true, if: :session_period?
  validates :user_id, presence: true, if: :user_period?

  validate :validate_period_associations
  validate :validate_date_range

  # Callbacks
  before_validation :set_default_analysis_data, on: :create

  # Scopes
  scope :by_period, ->(period) { where(period: period) }
  scope :sessions, -> { where(period: "session") }
  scope :daily_summaries, -> { where(period: "daily") }
  scope :weekly_summaries, -> { where(period: "weekly") }
  scope :monthly_summaries, -> { where(period: "monthly") }
  scope :in_date_range, ->(start_date, end_date) {
    where(tally_start_at: start_date..end_date)
  }
  scope :recent, -> { order(tally_start_at: :desc) }

  # Class Methods
  def self.find_or_create_for_period(user:, period:, start_at:, end_at:)
    find_or_create_by(
      user: user,
      period: period,
      tally_start_at: start_at,
      tally_end_at: end_at
    ) do |summary|
      summary.analysis_data = default_analysis_data
    end
  end

  def self.default_analysis_data
    {
      summary: "",
      insights: {},
      sentiment_overview: {},
      metrics: {}
    }
  end

  # Instance Methods
  def session_period?
    period == "session"
  end

  def user_period?
    period.in?([ "daily", "weekly", "monthly" ])
  end

  def duration_in_days
    ((tally_end_at - tally_start_at) / 1.day).to_i
  end

  def add_insight(key, value)
    insights = analysis_data["insights"] || {}
    insights[key.to_s] = value
    update!(analysis_data: analysis_data.merge("insights" => insights))
  end

  def add_metric(key, value)
    metrics = analysis_data["metrics"] || {}
    metrics[key.to_s] = value
    update!(analysis_data: analysis_data.merge("metrics" => metrics))
  end

  def update_summary(text)
    update!(analysis_data: analysis_data.merge("summary" => text))
  end

  def sentiment_score
    analysis_data.dig("sentiment_overview", "overall_score")
  end

  # AI分析結果を取得
  def ai_analysis_data
    analysis_data.slice("strengths", "thinking_patterns", "values")
  end

  # 新規分析が必要かチェック
  def needs_new_analysis?
    return false unless user

    # 全ユーザーメッセージ数（ユーザーとアシスタントの両方をカウント）
    total_messages = user.messages.count

    # 分析済みのデータが存在するかチェック
    analyzed_data_exists = analysis_data.present? && analysis_data["analyzed_at"].present?

    # 開発環境用に要件を緩和
    required_messages = Rails.env.development? ? 2 : 10
    required_new_messages = Rails.env.development? ? 2 : 6

    if !analyzed_data_exists
      # 初回分析の条件
      total_messages >= required_messages
    else
      # 前回分析以降の新規メッセージ数（ユーザーとアシスタントの両方をカウント）
      new_messages = user.messages.where("messages.sent_at > ?", analysis_data["analyzed_at"]).count
      # 追加分析の条件
      new_messages >= required_new_messages
    end
  end

  # 前回分析からの新規メッセージ数を取得
  def messages_since_analysis
    return 0 unless user
    return user.messages.count unless analysis_data.present? && analysis_data["analyzed_at"].present?

    user.messages.where("messages.sent_at > ?", analysis_data["analyzed_at"]).count
  end

  # 最後の分析からの経過日数
  def days_since_analysis
    ((Time.current - updated_at) / 1.day).round
  end

  # スコープ追加: ユーザーの分析結果
  def self.user_analyses(user_id)
    where(user_id: user_id, period: [ "weekly", "monthly" ])
      .order(created_at: :desc)
  end

  private

  def validate_period_associations
    if session_period? && user_id.present?
      errors.add(:user_id, "はセッションサマリーでは設定できません")
    elsif user_period? && chat_id.present?
      errors.add(:chat_id, "はユーザー期間サマリーでは設定できません")
    end
  end

  def validate_date_range
    return unless tally_start_at && tally_end_at

    if tally_end_at < tally_start_at
      errors.add(:tally_end_at, "は開始日時より後である必要があります")
    end
  end

  def set_default_analysis_data
    self.analysis_data ||= self.class.default_analysis_data
  end
end
