# frozen_string_literal: true

module Reports
  # パーソナルアドバイス生成
  class PersonalAdviceAnalyzer < BaseAnalyzer
    def analyze
      return default_response if messages.blank?

      # AI分析を試みる
      ai_result = analyze_with_ai
      return ai_result if ai_result.present?

      # フォールバック: 簡易分析
      simple_advice_analysis
    end

    private

    def analyze_with_ai
      prompt = build_prompt
      response = ai_service.chat(
        [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        temperature: 0.8,
        max_tokens: 1000
      )

      parse_advice_response(response["content"])
    rescue StandardError => e
      Rails.logger.error "AI分析エラー (PersonalAdviceAnalyzer): #{e.message}"
      nil
    end

    def build_prompt
      conversation_text = messages.last(10).join("\n")
      <<~PROMPT
        以下のユーザーの会話履歴を分析し、パーソナライズされたアドバイスをJSON形式で提供してください。

        会話履歴:
        #{conversation_text}

        以下のJSON形式で返してください：
        ```json
        {
          "personalAxis": "ユーザーの価値観の中心となる「軸」を1文で表現",
          "emotionalPatterns": {
            "summary": "感情パターンの傾向を要約",
            "details": ["具体的なパターン1", "具体的なパターン2"]
          },
          "coreValues": {
            "summary": "大切にしている価値観の要約",
            "pillars": ["価値観1", "価値観2", "価値観3"]
          },
          "actionGuidelines": {
            "career": "キャリアに関する行動指針",
            "relationships": "人間関係に関する行動指針",
            "lifePhilosophy": "生き方に関する指針"
          }
        }
        ```
      PROMPT
    end

    def system_prompt
      <<~PROMPT
        あなたは心理カウンセラーです。ユーザーの会話から感情状態、価値観、行動パターンを分析し、
        構造化されたパーソナルアドバイスを提供してください。
        温かく、共感的で、実践的な内容にしてください。
      PROMPT
    end

    def parse_advice_response(content)
      return default_response if content.blank?

      # JSONブロックを抽出してパース
      json_match = content.match(/```json\s*(.*?)\s*```/m) ||
                   content.match(/\{.*\}/m)

      if json_match
        parsed = JSON.parse(json_match[1] || json_match[0])
        return format_advice_response(parsed)
      end

      default_response
    rescue JSON::ParserError => e
      Rails.logger.error "JSONパースエラー (PersonalAdviceAnalyzer): #{e.message}"
      default_response
    end

    def format_advice_response(parsed)
      {
        personalAxis: parsed["personalAxis"] || "自己理解を深めながら、自分らしい道を探っています",
        emotionalPatterns: {
          summary: parsed.dig("emotionalPatterns", "summary") || "感情の変化を観察中です",
          details: parsed.dig("emotionalPatterns", "details") || []
        },
        coreValues: {
          summary: parsed.dig("coreValues", "summary") || "価値観を明確化しています",
          pillars: parsed.dig("coreValues", "pillars") || []
        },
        actionGuidelines: {
          career: parsed.dig("actionGuidelines", "career") || "自分の強みを活かせる方向を探りましょう",
          relationships: parsed.dig("actionGuidelines", "relationships") || "信頼できる関係を大切にしましょう",
          lifePhilosophy: parsed.dig("actionGuidelines", "lifePhilosophy") || "自分のペースで着実に進みましょう"
        }
      }
    end

    def simple_advice_analysis
      # 感情キーワードから簡易的なアドバイスを生成
      emotions = extract_emotions_from_messages
      dominant = dominant_emotion(emotions)

      base_advice = case dominant
      when "joy", "喜び"
        "素晴らしい気持ちを維持していますね。この前向きなエネルギーを大切にしてください。"
      when "sadness", "悲しみ"
        "辛い時期を過ごされているようです。自分に優しく、必要な時は休息を取ってください。"
      when "anxiety", "不安"
        "不確実性と向き合っているようです。一歩ずつ、着実に進んでいきましょう。"
      when "anger", "怒り"
        "感情を言語化できているのは素晴らしいことです。少しずつ整理していきましょう。"
      else
        "日々の会話を通じて、自己理解が深まっています。"
      end

      {
        personalAxis: base_advice,
        emotionalPatterns: {
          summary: "感情の変化を観察しています",
          details: emotions.uniq.map { |e| "#{e}を感じることがあります" }
        },
        coreValues: {
          summary: "あなたの価値観を理解しようとしています",
          pillars: ["自己理解", "成長", "安心"]
        },
        actionGuidelines: {
          career: "自分の強みを見つけていきましょう",
          relationships: "信頼できる人との関係を大切に",
          lifePhilosophy: "無理をせず、自分のペースで"
        }
      }
    end

    def extract_emotions_from_messages
      # メッセージから感情を抽出（簡易版）
      emotion_keywords = {
        joy: %w[嬉しい 楽しい 幸せ うれしい たのしい],
        sadness: %w[悲しい 辛い つらい 寂しい さみしい],
        anxiety: %w[不安 心配 怖い こわい 緊張],
        anger: %w[怒り イライラ 腹立 むかつく]
      }

      found_emotions = []
      messages.each do |msg|
        emotion_keywords.each do |emotion, keywords|
          if keywords.any? { |keyword| msg.include?(keyword) }
            found_emotions << emotion
          end
        end
      end

      found_emotions
    end

    def dominant_emotion(emotions)
      return nil if emotions.empty?

      emotions.group_by(&:itself)
              .transform_values(&:count)
              .max_by { |_, count| count }
              &.first
              &.to_s
    end

    def default_response
      {
        personalAxis: "日々の会話を通じて、自己理解が深まっています。この調子で続けてください。",
        emotionalPatterns: {
          summary: "感情パターンを分析中です",
          details: []
        },
        coreValues: {
          summary: "価値観を探求中です",
          pillars: []
        },
        actionGuidelines: {
          career: "自分の興味を探ってみましょう",
          relationships: "大切な人との時間を大切に",
          lifePhilosophy: "今の自分を受け入れることから始めましょう"
        }
      }
    end
  end
end