require "openai"
require "anthropic"
require "gemini-ai"

class AiServiceV2
  attr_reader :provider, :api_key

  def initialize(provider: "openai", api_key: nil)
    @provider = provider.to_s
    @api_key = api_key || fetch_api_key(provider)
    validate_api_key!
  end

  def chat(messages, model: nil, temperature: 0.7, max_tokens: 1000)
    case provider
    when "openai"
      openai_chat(messages, model: model || "gpt-4o-mini", temperature: temperature, max_tokens: max_tokens)
    when "anthropic"
      anthropic_chat(messages, model: model || "claude-3-5-sonnet-20241022", temperature: temperature, max_tokens: max_tokens)
    when "google"
      google_chat(messages, model: model || "gemini-1.5-flash", temperature: temperature, max_tokens: max_tokens)
    else
      raise "Unsupported AI provider: #{provider}"
    end
  end

  def build_messages(past_messages, system_prompt = nil)
    messages = []

    if system_prompt.present?
      messages << { role: "system", content: system_prompt }
    else
      messages << { role: "system", content: default_system_prompt }
    end

    past_messages.each do |msg|
      messages << { role: msg.role, content: msg.content }
    end

    messages
  end

  private

  def validate_api_key!
    raise "API key is required for #{provider}" if api_key.blank?
  end

  def fetch_api_key(provider)
    case provider.to_s
    when "openai"
      ENV["OPENAI_API_KEY"]
    when "anthropic"
      ENV["ANTHROPIC_API_KEY"]
    when "google"
      ENV["GOOGLE_API_KEY"]
    else
      nil
    end
  end

  def openai_chat(messages, model:, temperature:, max_tokens:)
    client = OpenAI::Client.new(access_token: api_key)

    response = client.chat(
      parameters: {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
    )

    if response.dig("error")
      raise StandardError, response.dig("error", "message")
    end

    {
      "content" => response.dig("choices", 0, "message", "content"),
      "model" => model,
      "provider" => "openai"
    }
  rescue => e
    Rails.logger.error "OpenAIエラー: #{e.message}"
    raise "OpenAI APIエラー: #{e.message}"
  end

  def anthropic_chat(messages, model:, temperature:, max_tokens:)
    client = Anthropic::Client.new(access_token: api_key)

    # Anthropic形式にメッセージを変換
    system_message = messages.find { |m| m[:role] == "system" }
    user_messages = messages.reject { |m| m[:role] == "system" }

    # Anthropicの形式に合わせて調整
    formatted_messages = user_messages.map do |msg|
      {
        role: msg[:role] == "assistant" ? "assistant" : "user",
        content: msg[:content]
      }
    end

    parameters = {
      model: model,
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    parameters[:system] = system_message[:content] if system_message

    response = client.messages(parameters: parameters)

    if response.dig("error")
      raise StandardError, response.dig("error", "message")
    end

    {
      "content" => response.dig("content", 0, "text"),
      "model" => model,
      "provider" => "anthropic"
    }
  rescue => e
    Rails.logger.error "Anthropicエラー: #{e.message}"
    raise "Anthropic APIエラー: #{e.message}"
  end

  def google_chat(messages, model:, temperature:, max_tokens:)
    client = Gemini.new(
      credentials: {
        service: "generative-language-api",
        api_key: api_key
      },
      options: {
        model: model,
        server_sent_events: true
      }
    )

    # Gemini形式にメッセージを変換
    contents = messages.map do |msg|
      role = case msg[:role]
      when "system" then "user"  # Geminiにはsystemロールがないため
      when "assistant" then "model"
      else "user"
      end

      {
        role: role,
        parts: [ { text: msg[:content] } ]
      }
    end

    response = client.generate_content(
      contents: contents,
      generation_config: {
        temperature: temperature,
        max_output_tokens: max_tokens
      }
    )

    if response.dig("error")
      raise StandardError, response.dig("error", "message")
    end

    content = response.dig("candidates", 0, "content", "parts", 0, "text") ||
              response.dig("candidates", 0, "text")

    {
      "content" => content,
      "model" => model,
      "provider" => "google"
    }
  rescue => e
    Rails.logger.error "Google Geminiエラー: #{e.message}"
    raise "Google Gemini APIエラー: #{e.message}"
  end

  def default_system_prompt
    # YAMLファイル (config/prompts.yml) から取得
    prompts_config = YAML.load_file(Rails.root.join("config", "prompts.yml"))
    env_prompts = prompts_config[Rails.env] || prompts_config["default"]
    env_prompts["system_prompt"]
  rescue => e
    Rails.logger.error "prompts.ymlの読み込みエラー: #{e.message}"
    raise "システムプロンプト設定が見つかりません。config/prompts.ymlを確認してください"
  end
end
