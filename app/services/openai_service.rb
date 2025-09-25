require "openai"

class OpenaiService
  CHAT_MODEL = AppConstants::AI::DEFAULT_MODEL
  MAX_TOKENS = AppConstants::AI::DEFAULT_MAX_TOKENS
  TEMPERATURE = AppConstants::AI::DEFAULT_TEMPERATURE

  def initialize(api_key = nil)
    @client = OpenAI::Client.new(
      access_token: api_key || ENV["OPENAI_API_KEY"],
      log_errors: true
    )
  end

  def chat(messages, options = {})
    model = options[:model] || CHAT_MODEL
    max_tokens = options[:max_tokens] || MAX_TOKENS
    temperature = options[:temperature] || TEMPERATURE

    response = @client.chat(
      parameters: {
        model: model,
        messages: messages,
        max_tokens: max_tokens,
        temperature: temperature
      }
    )

    if response.dig("error")
      raise StandardError, response.dig("error", "message")
    end

    response.dig("choices", 0, "message")
  rescue StandardError => e
    Rails.logger.error "OpenAI APIエラー: #{e.message}"
    raise e
  end

  def build_messages(chat_messages, system_prompt = nil)
    messages = []

    # システムプロンプトを追加
    if system_prompt.present?
      messages << { role: "system", content: system_prompt }
    else
      messages << {
        role: "system",
        content: default_system_prompt
      }
    end

    # 過去のメッセージを追加
    chat_messages.each do |msg|
      messages << {
        role: msg.role,
        content: msg.content
      }
    end

    messages
  end

  private

  def default_system_prompt
    <<~PROMPT
      あなたは「心のログ」というサービスのAIアシスタントです。
      ユーザーの感情や思考を言語化し、整理するお手伝いをします。
      以下の点を心がけてください：

      1. 共感的で温かい対応を心がける
      2. ユーザーの感情を否定せず、受け止める
      3. 適切な質問を通じて、思考を深掘りする
      4. 簡潔で分かりやすい言葉を使う
      5. 必要に応じて、感情や思考を整理・要約する

      ユーザーと対話しながら、自己理解を深められるようサポートしてください。
    PROMPT
  end
end
