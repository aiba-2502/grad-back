# frozen_string_literal: true

module Reports
  # 会話分析（週次・月次レポート）
  class ConversationAnalyzer < BaseAnalyzer
    def analyze(period = :week)
      messages_in_period = fetch_messages_for_period(period)

      {
        period: period.to_s,
        messageCount: messages_in_period.count,
        summary: generate_summary(messages_in_period),
        frequentKeywords: extract_frequent_keywords(messages_in_period),
        emotionKeywords: extract_emotion_keywords(messages_in_period),
        startDate: period_start_date(period),
        endDate: Time.current
      }
    end

    def weekly_report
      analyze(:week)
    end

    def monthly_report
      analyze(:month)
    end

    private

    def fetch_messages_for_period(period)
      time_range = period_start_date(period)..Time.current

      user.messages
          .where(sender_kind: Message::SENDER_USER)
          .where(sent_at: time_range)
    end

    def period_start_date(period)
      case period
      when :week
        1.week.ago
      when :month
        1.month.ago
      else
        1.week.ago
      end
    end

    def generate_summary(messages)
      return "メッセージがありません。" if messages.blank?

      # 簡易的なサマリー生成
      message_contents = messages.pluck(:content)

      # 感情分析
      emotions = analyze_emotions(message_contents)

      # トピック抽出
      topics = extract_topics(message_contents)

      build_summary(messages.count, emotions, topics)
    end

    def build_summary(count, emotions, topics)
      summary_parts = []

      summary_parts << "#{count}件のメッセージを記録しました。"

      if emotions.any?
        emotion_text = emotions.map { |e| e[:label] }.join("、")
        summary_parts << "主な感情: #{emotion_text}"
      end

      if topics.any?
        topic_text = topics.take(3).join("、")
        summary_parts << "主なトピック: #{topic_text}"
      end

      summary_parts.join(" ")
    end

    def analyze_emotions(message_contents)
      emotion_service = EmotionExtractionService.new
      emotions = []

      message_contents.each do |content|
        extracted = emotion_service.extract_emotions(content)
        emotions.concat(extracted) if extracted.present?
      end

      # 感情を集計
      emotion_counts = emotions.group_by { |e| e[:name] }
                               .transform_values(&:count)
                               .sort_by { |_, count| -count }
                               .take(3)

      emotion_counts.map do |name, count|
        tag = Tag.find_by(name: name, category: "emotion")
        {
          name: name,
          label: tag&.metadata&.dig("label_ja") || name,
          count: count
        }
      end
    end

    def extract_topics(message_contents)
      all_keywords = message_contents.flat_map { |content| extract_keywords(content) }

      # 頻出キーワードを抽出
      keyword_counts = all_keywords.group_by(&:itself)
                                   .transform_values(&:count)
                                   .sort_by { |_, count| -count }

      # 上位5つのトピックを返す
      keyword_counts.take(5).map(&:first)
    end

    def extract_frequent_keywords(messages)
      return [] if messages.blank?

      all_keywords = messages.pluck(:content).flat_map { |content| extract_keywords(content) }

      keyword_counts = all_keywords.group_by(&:itself)
                                   .transform_values(&:count)
                                   .sort_by { |_, count| -count }
                                   .take(10)

      keyword_counts.map do |keyword, count|
        {
          word: keyword,
          count: count,
          percentage: (count.to_f / all_keywords.size * 100).round(1)
        }
      end
    end

    def extract_emotion_keywords(messages)
      return [] if messages.blank?

      # 感情と同じメッセージに含まれるキーワードをマッピング
      emotion_keyword_map = {}

      messages.each do |message|
        emotions = message.emotion_keywords || []
        # メッセージからキーワードを抽出
        keywords = extract_keywords(message.content)

        emotions.each do |emotion|
          emotion_keyword_map[emotion] ||= []
          emotion_keyword_map[emotion].concat(keywords)
        end
      end

      # 感情ごとにキーワードを集計
      emotion_keyword_map.map do |emotion, keywords|
        # キーワードの出現頻度でソートして上位を取得
        keyword_counts = keywords.group_by(&:itself)
                                 .transform_values(&:count)
                                 .sort_by { |_, count| -count }
                                 .take(5)
                                 .map { |k, _| k }

        # 感情タグから日本語ラベルを取得
        tag = Tag.find_by(name: emotion, category: "emotion")
        emotion_label = tag&.metadata&.dig("label_ja") || emotion

        {
          emotion: emotion_label,
          keywords: keyword_counts
        }
      end.reject { |item| item[:keywords].empty? }
    end
  end
end