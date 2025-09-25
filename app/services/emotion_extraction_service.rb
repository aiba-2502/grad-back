class EmotionExtractionService
  def initialize(ai_service: nil)
    @ai_service = ai_service
    @emotion_tags = load_emotion_tags
  end

  def extract_emotions(message_content)
    return [] if message_content.blank?
    return fallback_emotion_detection(message_content) if @ai_service.nil?

    # AI を使用して感情を分析
    emotions = analyze_with_ai(message_content)

    # 感情の強度を計算して返す
    emotions.select { |e| e[:intensity] >= 0.3 }
  rescue StandardError => e
    Rails.logger.error "感情抽出エラー: #{e.message}"
    # エラー時は簡易的な感情分析を行う
    fallback_emotion_detection(message_content)
  end

  private

  def load_emotion_tags
    # Load only active emotion tags from database with caching
    Rails.cache.fetch("emotion_tags", expires_in: 1.hour) do
      Tag.where(category: "emotion", is_active: true).map do |tag|
        {
          name: tag.name.to_sym,
          label_ja: tag.metadata["label_ja"],
          label_en: tag.metadata["label_en"],
          color: tag.metadata["color"],
          intensity_default: tag.metadata["intensity_default"] || 0.5
        }
      end
    end
  end

  def emotion_categories
    # Build emotion categories hash from database tags
    @emotion_tags.each_with_object({}) do |tag, hash|
      hash[tag[:name]] = tag[:label_ja]
    end
  end

  def analyze_with_ai(content)
    prompt = build_emotion_prompt(content)

    messages = [
      { role: "system", content: emotion_analysis_system_prompt },
      { role: "user", content: prompt }
    ]

    response = @ai_service.chat(
      messages,
      temperature: 0.3,
      max_tokens: 200
    )

    parse_emotion_response(response["content"])
  end

  def emotion_analysis_system_prompt
    categories = emotion_categories
    <<~PROMPT
      あなたは感情分析の専門家です。
      ユーザーのメッセージから感情を分析し、JSON形式で返してください。

      以下の感情カテゴリーから該当するものを選んでください：
      #{categories.map { |k, v| "#{k}(#{v})" }.join(', ')}

      回答は必ず以下のJSON形式で返してください：
      {
        "emotions": [
          {"name": "感情名(英語)", "intensity": 0.0〜1.0の数値}
        ]
      }

      注意事項：
      - 複数の感情が含まれる場合は、全て列挙してください
      - intensityは感情の強さを0.0〜1.0で表してください
      - 最大3つまでの主要な感情を返してください
    PROMPT
  end

  def build_emotion_prompt(content)
    "以下のメッセージから感情を分析してください：\n\n#{content}"
  end

  def parse_emotion_response(response)
    # JSON部分を抽出
    json_match = response.match(/\{.*\}/m)
    return [] unless json_match

    json_data = JSON.parse(json_match[0])
    emotions = json_data["emotions"] || []
    categories = emotion_categories

    emotions.map do |emotion|
      {
        name: emotion["name"].to_sym,
        intensity: emotion["intensity"].to_f,
        label: categories[emotion["name"].to_sym] || emotion["name"]
      }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "感情JSONパースエラー: #{e.message}"
    []
  end

  def fallback_emotion_detection(content)
    # 簡易的なキーワードベースの感情検出
    emotions = []

    # 感情を表すキーワードと対応する感情カテゴリー
    emotion_keywords = build_emotion_keywords

    emotion_keywords.each do |emotion, keywords|
      if keywords.any? { |keyword| content.include?(keyword) }
        tag = @emotion_tags.find { |t| t[:name] == emotion }
        emotions << {
          name: emotion,
          intensity: tag ? tag[:intensity_default] : 0.5,
          label: tag ? tag[:label_ja] : emotion.to_s
        }
      end
    end

    emotions.take(3) # 最大3つまで
  end

  def build_emotion_keywords
    # Build keyword mappings from database or use defaults
    {
      joy: %w[嬉しい 楽しい 幸せ 最高 ワクワク うれしい たのしい しあわせ],
      sadness: %w[悲しい 寂しい つらい 切ない かなしい さびしい さみしい],
      anger: %w[腹立つ むかつく イライラ 怒り いらいら ムカツク],
      fear: %w[怖い 恐い 不安 心配 こわい ふあん しんぱい],
      anxiety: %w[不安 心配 気がかり 落ち着かない],
      relief: %w[安心 ほっと 落ち着 あんしん],
      gratitude: %w[ありがとう 感謝 お礼 かんしゃ],
      frustration: %w[もどかしい イライラ ストレス いらいら],
      hope: %w[希望 期待 楽しみ きぼう きたい],
      disappointment: %w[がっかり 残念 失望 ざんねん]
    }
  end
end
