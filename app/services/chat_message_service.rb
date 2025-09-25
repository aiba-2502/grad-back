# frozen_string_literal: true

# チャットメッセージ処理サービス
class ChatMessageService
  attr_reader :user, :chat

  def initialize(user:, session_id: nil)
    @user = user
    @session_id = session_id || generate_session_id
    @chat = find_or_create_chat
  end

  def create_message(content:, provider: nil, api_key: nil, system_prompt: nil, model: nil, temperature: nil, max_tokens: nil)
    ActiveRecord::Base.transaction do
      # 感情抽出
      emotions = extract_emotions(content, provider, api_key)

      # ユーザーメッセージを保存
      user_message = save_user_message(content, emotions)

      # AI応答を生成
      ai_response = generate_ai_response(
        content: content,
        provider: provider,
        api_key: api_key,
        system_prompt: system_prompt,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens
      )

      # アシスタントメッセージを保存
      assistant_message = save_assistant_message(ai_response)

      {
        session_id: @session_id,
        chat_id: @chat.id,
        user_message: serialize_message(user_message),
        assistant_message: serialize_message(assistant_message)
      }
    end
  rescue StandardError => e
    Rails.logger.error "チャットエラー: #{e.message}"
    raise
  end

  def list_messages(page: 1, per_page: nil)
    per_page ||= AppConstants::DEFAULT_PAGE_SIZE

    messages = Message.where(chat: @chat)
                     .order(sent_at: :asc)
                     .page(page)
                     .per(per_page)

    {
      messages: messages.map { |msg| serialize_message(msg) },
      total_count: messages.total_count,
      current_page: messages.current_page,
      total_pages: messages.total_pages
    }
  end

  def destroy_session
    return { error: "セッションが見つかりません" } unless @chat

    deleted_count = Message.where(chat: @chat).destroy_all.count
    @chat.destroy

    { message: "セッションを正常に削除しました", deleted_count: deleted_count }
  end

  private

  def generate_session_id
    SecureRandom.uuid
  end

  def find_or_create_chat
    Chat.find_or_create_by!(
      title: "session:#{@session_id}",
      user: @user
    )
  end

  def extract_emotions(content, provider, api_key)
    provider ||= "openai"
    ai_service = AiServiceV2.new(provider: provider, api_key: api_key)
    emotion_service = EmotionExtractionService.new(ai_service: ai_service)

    emotion_service.extract_emotions(content)
  rescue StandardError => e
    Rails.logger.error "感情抽出エラー: #{e.message}"
    []
  end

  def save_user_message(content, emotions)
    emotion_score = emotions.any? ? emotions.map { |e| e[:intensity] || 0.5 }.sum / emotions.size : 0.0
    emotion_keywords = emotions.map { |e| e[:name].to_s }

    Message.create!(
      chat: @chat,
      sender: @user,
      content: content,
      sender_kind: Message::SENDER_USER,
      emotion_score: emotion_score,
      emotion_keywords: emotion_keywords,
      llm_metadata: {
        timestamp: Time.current.to_i,
        device: "web"
      },
      sent_at: Time.current
    )
  end

  def generate_ai_response(params)
    # 過去のメッセージを取得
    past_messages = Message.joins(:chat)
                          .where(chat: @chat)
                          .order(sent_at: :asc)
                          .last(AppConstants::MAX_PAST_MESSAGES)

    # AIサービスを初期化
    provider = params[:provider] || "openai"
    api_key = params[:api_key]
    ai_service = AiServiceV2.new(provider: provider, api_key: api_key)

    # 動的プロンプトを生成（必要に応じて）
    system_prompt, temperature = prepare_ai_params(params, past_messages)

    # メッセージを構築
    messages = build_ai_messages(past_messages, system_prompt, params[:content])

    # AIの応答を取得
    Rails.logger.info "AI呼び出し - temperature: #{temperature}, max_tokens: #{params[:max_tokens]&.to_i}"

    ai_service.chat(
      messages,
      model: params[:model],
      temperature: temperature,
      max_tokens: params[:max_tokens]&.to_i
    )
  end

  def prepare_ai_params(params, past_messages)
    system_prompt = params[:system_prompt]
    temperature = params[:temperature]&.to_f

    if system_prompt.blank?
      # 動的プロンプト生成
      chat_messages = convert_to_chat_messages(past_messages)
      prompt_service = DynamicPromptService.new(chat_messages)

      system_prompt = prompt_service.generate_system_prompt
      temperature ||= prompt_service.recommended_temperature
    end

    temperature ||= 0.7

    [ system_prompt, temperature ]
  end

  def convert_to_chat_messages(messages)
    messages.map do |msg|
      OpenStruct.new(
        content: msg.content,
        role: msg.sender_id == @user.id ? "user" : "assistant",
        emotions: msg.emotion_keywords&.map { |k| { name: k, intensity: msg.emotion_score } }
      )
    end
  end

  def build_ai_messages(past_messages, system_prompt, current_content)
    messages = past_messages[0...-1].map do |msg|
      {
        role: msg.sender_id == @user.id ? "user" : "assistant",
        content: msg.content
      }
    end

    # システムプロンプトを追加
    messages.unshift({ role: "system", content: system_prompt }) if system_prompt.present?

    # 今回のユーザーメッセージを追加
    messages << { role: "user", content: current_content }

    messages
  end

  def save_assistant_message(ai_response)
    Message.create!(
      chat: @chat,
      sender: @user,
      content: ai_response["content"],
      sender_kind: Message::SENDER_ASSISTANT,
      llm_metadata: {
        model: ai_response["model"],
        provider: ai_response["provider"],
        timestamp: Time.current.to_i,
        role: "assistant"
      },
      sent_at: Time.current
    )
  end

  def serialize_message(message)
    {
      id: message.id,
      content: message.content,
      role: message.sender_kind == Message::SENDER_USER ? "user" : "assistant",
      session_id: @session_id,
      metadata: message.llm_metadata,
      emotions: serialize_emotions(message),
      created_at: message.sent_at || message.created_at,
      updated_at: message.updated_at
    }
  end

  def serialize_emotions(message)
    return [] unless message.emotion_keywords.present?

    message.emotion_keywords.map do |keyword|
      tag = emotion_tag(keyword)
      {
        name: keyword,
        label: tag&.metadata&.dig("label_ja") || keyword,
        intensity: message.emotion_score
      }
    end
  end

  def emotion_tag(name)
    @emotion_tags_cache ||= load_emotion_tags_cache
    @emotion_tags_cache[name]
  end

  def load_emotion_tags_cache
    Rails.cache.fetch("emotion_tags_map", expires_in: 1.hour) do
      Tag.where(category: "emotion", is_active: true).index_by(&:name)
    end
  end
end