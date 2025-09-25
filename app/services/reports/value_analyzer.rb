# frozen_string_literal: true

module Reports
  # 価値観分析
  class ValueAnalyzer < BaseAnalyzer
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
      Rails.logger.error "AI分析エラー (ValueAnalyzer): #{e.message}"
      nil
    end

    def build_prompt
      conversation_text = messages.join("\n")
      <<~PROMPT
        以下のユーザーの会話履歴から、大切にしている価値観を3つ分析してください。

        会話履歴:
        #{conversation_text}

        以下のJSON形式で返してください:
        ```json
        {
          "values": [
            {
              "id": "UUID",
              "title": "価値観のタイトル",
              "description": "価値観の詳細説明"
            }
          ]
        }
        ```
      PROMPT
    end

    def system_prompt
      "あなたは価値観分析の専門家です。ユーザーが大切にしている価値観を見つけ出し、それを肯定的に評価してください。"
    end

    def format_response(parsed_response)
      return nil unless parsed_response&.dig("values")

      parsed_response["values"].map do |value|
        {
          id: value["id"] || SecureRandom.uuid,
          title: value["title"],
          description: value["description"]
        }
      end
    end

    def keyword_based_analysis
      keywords = messages.flat_map { |msg| extract_keywords(msg) }
      values = []

      # 家族・人間関係の価値観
      if keywords.any? { |k| k =~ /家族|友人|仲間|大切な人/ }
        values << {
          id: SecureRandom.uuid,
          title: "人間関係",
          description: "家族や友人との繋がりを大切にしています。"
        }
      end

      # 成長・学習の価値観
      if keywords.any? { |k| k =~ /学ぶ|成長|挑戦|新しい/ }
        values << {
          id: SecureRandom.uuid,
          title: "自己成長",
          description: "常に学び、成長することを重視しています。"
        }
      end

      # 健康・ウェルビーイングの価値観
      if keywords.any? { |k| k =~ /健康|休息|リラックス|バランス/ }
        values << {
          id: SecureRandom.uuid,
          title: "健康とバランス",
          description: "心身の健康とライフバランスを重視しています。"
        }
      end

      values.presence || default_response
    end

    def default_response
      [
        {
          id: SecureRandom.uuid,
          title: "誠実さ",
          description: "自分自身に正直であることを大切にしています。"
        },
        {
          id: SecureRandom.uuid,
          title: "成長",
          description: "日々の経験から学び、成長することを重視しています。"
        },
        {
          id: SecureRandom.uuid,
          title: "調和",
          description: "自分と周囲との調和を保つことを大切にしています。"
        }
      ]
    end
  end
end