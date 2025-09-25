# frozen_string_literal: true

module Reports
  # 思考パターン分析
  class ThinkingPatternAnalyzer < BaseAnalyzer
    def analyze
      return default_response if messages.blank?

      # AI分析を試みる
      ai_result = analyze_with_ai
      return ai_result if ai_result.present?

      # フォールバック
      keyword_based_analysis
    end

    private

    def analyze_with_ai
      prompt = build_prompt
      response = ai_service.chat(
        [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        temperature: 0.7,
        max_tokens: 800
      )

      format_response(parse_ai_response(response["content"]))
    rescue StandardError => e
      Rails.logger.error "AI分析エラー (ThinkingPatternAnalyzer): #{e.message}"
      nil
    end

    def build_prompt
      conversation_text = messages.join("\n")
      <<~PROMPT
        以下のユーザーの会話履歴から、思考パターンを3つ分析してください。

        会話履歴:
        #{conversation_text}

        以下のJSON形式で返してください:
        ```json
        {
          "patterns": [
            {
              "id": "UUID",
              "title": "思考パターンのタイトル",
              "description": "パターンの詳細説明"
            }
          ]
        }
        ```
      PROMPT
    end

    def system_prompt
      "あなたは認知心理学の専門家です。ユーザーの思考パターンを分析し、建設的なフィードバックを提供してください。"
    end

    def format_response(parsed_response)
      return nil unless parsed_response&.dig("patterns")

      parsed_response["patterns"].map do |pattern|
        {
          id: pattern["id"] || SecureRandom.uuid,
          title: pattern["title"],
          description: pattern["description"]
        }
      end
    end

    def keyword_based_analysis
      keywords = messages.flat_map { |msg| extract_keywords(msg) }
      patterns = []

      # 論理的思考のチェック
      if keywords.any? { |k| k =~ /なぜ|理由|原因|結果/ }
        patterns << {
          id: SecureRandom.uuid,
          title: "論理的思考",
          description: "物事の原因と結果を論理的に考える傾向があります。"
        }
      end

      # 感情的思考のチェック
      if keywords.any? { |k| k =~ /感じ|思う|気持ち|心/ }
        patterns << {
          id: SecureRandom.uuid,
          title: "感情重視",
          description: "感情や直感を大切にする思考パターンです。"
        }
      end

      # 未来志向のチェック
      if keywords.any? { |k| k =~ /将来|明日|今後|目標/ }
        patterns << {
          id: SecureRandom.uuid,
          title: "未来志向",
          description: "将来のことを考えて行動する傾向があります。"
        }
      end

      patterns.presence || default_response
    end

    def default_response
      [
        {
          id: SecureRandom.uuid,
          title: "内省的思考",
          description: "自分の内面と向き合い、深く考える傾向があります。"
        },
        {
          id: SecureRandom.uuid,
          title: "バランス型",
          description: "感情と論理のバランスを取りながら考えます。"
        },
        {
          id: SecureRandom.uuid,
          title: "成長志向",
          description: "常に改善点を見つけて成長しようとします。"
        }
      ]
    end
  end
end