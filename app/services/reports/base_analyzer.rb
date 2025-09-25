# frozen_string_literal: true

module Reports
  # 分析器の基底クラス
  class BaseAnalyzer
    attr_reader :user, :messages, :ai_service

    def initialize(user:, messages: nil)
      @user = user
      @messages = messages || fetch_messages
      @ai_service = OpenaiService.new
    end

    # 分析実行（サブクラスで実装）
    def analyze
      raise NotImplementedError, "サブクラスで#analyzeメソッドを実装してください"
    end

    protected

    # メッセージ取得
    def fetch_messages(period = 1.month)
      user.messages
          .where(sender_kind: Message::SENDER_USER)
          .where("sent_at >= ?", period.ago)
          .pluck(:content)
    end

    # AI応答のパース
    def parse_ai_response(content)
      return nil if content.blank?

      # JSONブロックを抽出
      json_match = content.match(/```json\s*(.*?)\s*```/m) ||
                   content.match(/\{.*\}/m)
      return nil unless json_match

      JSON.parse(json_match[1] || json_match[0])
    rescue JSON::ParserError => e
      Rails.logger.error "JSONパースエラー (#{self.class.name}): #{e.message}"
      nil
    end

    # システムプロンプト（サブクラスでオーバーライド可能）
    def system_prompt
      "あなたは心理カウンセラーです。ユーザーの会話から洞察を提供してください。"
    end

    # デフォルトレスポンス（サブクラスでオーバーライド）
    def default_response
      []
    end

    # キーワード抽出
    def extract_keywords(text)
      return [] if text.blank?

      # 基本的なキーワード抽出（サブクラスで拡張可能）
      text.split(/[、。\s]+/)
          .select { |word| word.length > 1 }
          .map(&:strip)
          .reject(&:empty?)
          .uniq
    end
  end
end