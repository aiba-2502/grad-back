# frozen_string_literal: true

# レポート生成サービス（リファクタリング版）
class ReportService
  attr_reader :user

  def initialize(user)
    @user = user
    @analyzers = {
      strengths: Reports::StrengthAnalyzer.new(user: user),
      thinking_patterns: Reports::ThinkingPatternAnalyzer.new(user: user),
      values: Reports::ValueAnalyzer.new(user: user),
      conversations: Reports::ConversationAnalyzer.new(user: user)
    }
    @keyword_extractor = Extractors::KeywordExtractor.new
    @emotion_service = EmotionExtractionService.new
  end

  def generate_report
    existing_summary = find_or_create_current_summary

    if existing_summary.needs_new_analysis?
      {
        needsAnalysis: true,
        lastAnalyzedAt: existing_summary.analysis_data["analyzed_at"] || existing_summary.updated_at,
        existingData: parse_existing_analysis(existing_summary),
        message: "新しいメッセージが追加されました。AI分析を実行できます。",
        messagesSinceAnalysis: existing_summary.messages_since_analysis
      }
    else
      result = parse_existing_analysis(existing_summary)
      result[:needsAnalysis] = false
      result[:lastAnalyzedAt] = existing_summary.analysis_data["analyzed_at"] || existing_summary.updated_at
      result
    end
  end

  def execute_analysis
    Rails.logger.info "Executing AI analysis for user #{user.id}"

    analysis_result = {
      userId: user.id.to_s,
      userName: user.name,
      strengths: @analyzers[:strengths].analyze,
      thinkingPatterns: @analyzers[:thinking_patterns].analyze,
      values: @analyzers[:values].analyze,
      personalAdvice: generate_personal_advice,
      conversationReport: {
        week: @analyzers[:conversations].weekly_report,
        month: @analyzers[:conversations].monthly_report
      },
      updatedAt: Time.current.iso8601
    }

    save_to_summary(analysis_result)
    analysis_result
  end

  def generate_weekly_report
    @analyzers[:conversations].weekly_report
  end

  def generate_monthly_report
    @analyzers[:conversations].monthly_report
  end

  def generate_period_report(period, start_date = nil)
    period_days = period == "weekly" ? 7 : 30
    start_date ||= period_days.days.ago

    messages = user.messages
                   .where(sender_kind: Message::SENDER_USER)
                   .where("sent_at >= ?", start_date)

    analyzed_data = analyze_conversations(messages)

    {
      period: period,
      summary: generate_report_text(analyzed_data),
      frequentKeywords: @keyword_extractor.extract_from_messages(messages),
      emotionKeywords: extract_emotion_keywords_from_messages(messages),
      messageCount: messages.count,
      startDate: start_date,
      endDate: Time.current
    }
  end

  private

  def find_or_create_current_summary
    Summary.find_or_create_by(
      user_id: user.id,
      period: "monthly",
      tally_start_at: Time.current.beginning_of_month,
      tally_end_at: Time.current.end_of_month
    )
  end

  def parse_existing_analysis(summary)
    data = summary.analysis_data || {}

    {
      userId: user.id.to_s,
      userName: user.name,
      strengths: data["strengths"] || [],
      thinkingPatterns: data["thinking_patterns"] || [],
      values: data["values"] || [],
      personalAdvice: data["personal_advice"] || generate_personal_advice,
      conversationReport: data["conversation_report"] || {
        week: @analyzers[:conversations].weekly_report,
        month: @analyzers[:conversations].monthly_report
      },
      updatedAt: (summary.updated_at || Time.current).iso8601
    }
  end

  def save_to_summary(analysis_result)
    summary = find_or_create_current_summary

    summary.update!(
      analysis_data: {
        strengths: analysis_result[:strengths],
        thinking_patterns: analysis_result[:thinkingPatterns],
        values: analysis_result[:values],
        personal_advice: analysis_result[:personalAdvice],
        conversation_report: analysis_result[:conversationReport],
        analyzed_at: Time.current
      }
    )
  end

  def generate_personal_advice
    recent_messages = user.messages
                          .where(sender_kind: Message::SENDER_USER)
                          .where("sent_at >= ?", 1.week.ago)
                          .pluck(:content)

    return default_personal_advice if recent_messages.blank?

    # 感情分析に基づくアドバイス
    emotions = recent_messages.flat_map { |msg| @emotion_service.extract_emotions(msg) }

    build_personal_advice(emotions)
  end

  def build_personal_advice(emotions)
    dominant_emotion = emotions.group_by { |e| e[:name] }
                              .transform_values(&:count)
                              .max_by { |_, count| count }
                              &.first

    case dominant_emotion
    when "joy", "喜び"
      "素晴らしい気持ちを維持していますね。この前向きなエネルギーを大切にしてください。"
    when "sadness", "悲しみ"
      "辛い時期を過ごされているようです。自分に優しく、必要な時は休息を取ってください。"
    when "anxiety", "不安"
      "不確実性と向き合っているようです。一歩ずつ、着実に進んでいきましょう。"
    else
      default_personal_advice
    end
  end

  def default_personal_advice
    "日々の会話を通じて、自己理解が深まっています。この調子で続けてください。"
  end

  def analyze_conversations(messages)
    {
      message_count: messages.count,
      topics: extract_topics(messages),
      emotions: extract_emotions(messages)
    }
  end

  def extract_topics(messages)
    messages.flat_map { |msg| @keyword_extractor.extract(msg.content).map { |k| k[:word] } }
  end

  def extract_emotions(messages)
    # messagesが文字列の場合はEmotionExtractionServiceを使用（テスト互換性）
    if messages.is_a?(String)
      emotions = @emotion_service.extract_emotions(messages)
      return emotions.map { |e| e[:label] || e[:name] }
    end

    messages.flat_map { |msg| msg.emotion_keywords || [] }
  end

  def generate_report_text(analyzed_data)
    return "この期間の会話履歴はありません。" if analyzed_data[:message_count] == 0

    build_report_summary(analyzed_data)
  end

  def build_report_summary(data)
    summary_parts = []

    # トピック分析
    if data[:topics].any?
      topic_counts = data[:topics].tally
      main_topics = topic_counts.sort_by { |_, count| -count }.take(3).map(&:first)
      summary_parts << "主なトピック: #{main_topics.join('、')}"
    end

    # 感情分析
    if data[:emotions].any?
      emotion_counts = data[:emotions].tally
      main_emotions = emotion_counts.sort_by { |_, count| -count }.take(2).map(&:first)
      summary_parts << emotion_summary(main_emotions.first)
    end

    # メッセージ数に基づく追加情報
    summary_parts << activity_summary(data[:message_count])

    summary_parts.compact.join(" ")
  end

  def emotion_summary(dominant_emotion)
    case dominant_emotion
    when "喜び", "joy"
      "前向きな気持ちで過ごされています。"
    when "悲しみ", "sadness"
      "感情を大切に向き合っています。"
    when "不安", "anxiety"
      "慎重に状況に対応されています。"
    else
      "様々な感情を経験されています。"
    end
  end

  def activity_summary(message_count)
    if message_count >= 10
      "積極的な対話を通じて自己理解が深まっています。"
    elsif message_count >= 5
      "対話を通じて新たな気づきを得られています。"
    else
      "さらに対話を続けることで、より詳細な分析が可能になります。"
    end
  end

  def extract_emotion_keywords_from_messages(messages)
    emotions = messages.flat_map { |msg| msg.emotion_keywords || [] }

    emotions.tally
           .sort_by { |_, count| -count }
           .take(5)
           .map do |emotion, count|
             tag = Tag.find_by(name: emotion, category: "emotion")
             {
               name: emotion,
               label: tag&.metadata&.dig("label_ja") || emotion,
               count: count
             }
           end
  end

  # 互換性のためのヘルパーメソッド
  def extract_keywords_from_text(text)
    @keyword_extractor.extract(text).map { |k| k[:word] }
  end

  def detect_multiple_emotions(text)
    emotions = @emotion_service.extract_emotions(text)
    return ["その他"] if emotions.blank?

    emotions.map { |e| e[:name] }
  end

  def detect_emotion(text)
    emotions = @emotion_service.extract_emotions(text)
    emotions.first&.dig(:name) || "その他"
  end
end