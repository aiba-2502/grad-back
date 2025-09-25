# frozen_string_literal: true

module Reports
  # ユーザーの強み分析
  class StrengthAnalyzer < BaseAnalyzer
    def analyze
      return default_response if messages.blank?

      # AI分析を試みる
      ai_result = analyze_with_ai
      return ai_result if ai_result.present?

      # フォールバック: キーワードベース分析
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
      Rails.logger.error "AI分析エラー (StrengthAnalyzer): #{e.message}"
      nil
    end

    def build_prompt
      conversation_text = messages.join("\n")
      <<~PROMPT
        以下のユーザーの会話履歴から、ユーザーの強みを3つ分析してください。
        各強みについて、タイトルと説明を含めてJSON形式で返してください。

        会話履歴:
        #{conversation_text}

        以下のJSON形式で返してください:
        ```json
        {
          "strengths": [
            {
              "id": "UUID",
              "title": "強みのタイトル",
              "description": "強みの詳細説明"
            }
          ]
        }
        ```
      PROMPT
    end

    def system_prompt
      "あなたは心理カウンセラーです。ユーザーの会話から強みを見つけて励ましの言葉を提供してください。"
    end

    def format_response(parsed_response)
      return nil unless parsed_response&.dig("strengths")

      parsed_response["strengths"].map do |strength|
        {
          id: strength["id"] || SecureRandom.uuid,
          title: strength["title"],
          description: strength["description"]
        }
      end
    end

    def keyword_based_analysis
      # キーワードベースの簡易分析
      keywords = messages.flat_map { |msg| extract_keywords(msg) }

      strengths = []

      # 成長関連のキーワードをチェック
      if keywords.any? { |k| k =~ /成長|学習|勉強|挑戦/ }
        strengths << {
          id: SecureRandom.uuid,
          title: "成長意欲",
          description: "新しいことを学び、成長しようとする意欲が見られます。"
        }
      end

      # ポジティブなキーワードをチェック
      if keywords.any? { |k| k =~ /頑張|努力|前向き|楽しい/ }
        strengths << {
          id: SecureRandom.uuid,
          title: "前向きな姿勢",
          description: "困難な状況でも前向きに取り組む姿勢が素晴らしいです。"
        }
      end

      # 人間関係のキーワードをチェック
      if keywords.any? { |k| k =~ /友達|家族|仲間|協力/ }
        strengths << {
          id: SecureRandom.uuid,
          title: "協調性",
          description: "周囲との良好な関係を築く力があります。"
        }
      end

      strengths.presence || default_response
    end

    def default_response
      [
        {
          id: SecureRandom.uuid,
          title: "継続力",
          description: "日々の活動を継続する力があります。"
        },
        {
          id: SecureRandom.uuid,
          title: "自己理解",
          description: "自分の感情や思考を言語化できる能力があります。"
        },
        {
          id: SecureRandom.uuid,
          title: "成長意欲",
          description: "より良い自分になろうとする意欲が感じられます。"
        }
      ]
    end
  end
end