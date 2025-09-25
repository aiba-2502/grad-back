# frozen_string_literal: true

# 動的プロンプト制御システムの設定
module DynamicPromptConfig
  # 会話の段階管理設定
  # 各段階のメッセージ回数範囲を定義
  CONVERSATION_STAGES = {
    initial: {
      range: (0..2),
      description: "初期段階：理解と共感を重視"
    },
    exploring: {
      range: (3..5),
      description: "探索段階：適度な深掘り"
    },
    deepening: {
      range: (6..8),
      description: "深化段階：整理とまとめ"
    },
    concluding: {
      range: (9..),
      description: "終結段階：自然な締めくくり"
    }
  }.freeze

  # 温度パラメータの動的調整設定
  # 各段階における推奨温度を定義
  TEMPERATURE_SETTINGS = {
    initial: 0.6,      # 安定した応答
    exploring: 0.7,    # 少し創造的
    deepening: 0.5,    # 整理重視
    concluding: 0.4,   # 一貫性重視
    default: 0.6       # デフォルト値
  }.freeze

  # 会話の最大回数設定
  # この回数を超えると強制的に終了を促す
  MAX_CONVERSATION_TURNS = 10

  # 感情分析のためのキーワード設定
  EMOTION_KEYWORDS = {
    satisfaction: %w[
      ありがとう スッキリ 分かった 理解 納得 そうか なるほど
      助かった 嬉しい 良かった 安心 解決
    ].freeze,

    confusion: %w[
      分からない 難しい 混乱 どうしたら 迷って 不安
      よくわからない 複雑 整理できない
    ].freeze,

    closing: %w[
      じゃあ では それでは またね ばいばい 失礼
      おやすみ ありがとうございました 終わり
    ].freeze
  }.freeze

  # 短い返答と判定する文字数
  SHORT_RESPONSE_THRESHOLD = 10

  # 内容の類似度判定の閾値
  SIMILARITY_THRESHOLD = 0.6

  # 設定値を取得するヘルパーメソッド
  class << self
    def stage_range(stage)
      CONVERSATION_STAGES.dig(stage, :range)
    end

    def stage_description(stage)
      CONVERSATION_STAGES.dig(stage, :description)
    end

    def temperature_for_stage(stage)
      TEMPERATURE_SETTINGS[stage] || TEMPERATURE_SETTINGS[:default]
    end

    def satisfaction_keywords
      EMOTION_KEYWORDS[:satisfaction]
    end

    def confusion_keywords
      EMOTION_KEYWORDS[:confusion]
    end

    def closing_keywords
      EMOTION_KEYWORDS[:closing]
    end
  end
end
