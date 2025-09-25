# frozen_string_literal: true

class Api::V1::ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat_service, only: [ :create, :index ]
  before_action :set_session_chat_service, only: [ :destroy_session ]

  def create
    result = @chat_service.create_message(
      content: chat_params[:content],
      provider: chat_params[:provider],
      api_key: chat_params[:api_key],
      system_prompt: chat_params[:system_prompt],
      model: chat_params[:model],
      temperature: chat_params[:temperature],
      max_tokens: chat_params[:max_tokens]
    )

    render json: result, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    if params[:session_id].present?
      result = @chat_service.list_messages(
        page: params[:page],
        per_page: params[:per_page]
      )

      render json: result
    else
      # 全てのチャットからメッセージを取得
      messages = Message.joins(:chat)
                       .where(chats: { user_id: current_user.id })
                       .order(sent_at: :asc)
                       .page(params[:page])
                       .per(params[:per_page] || AppConstants::DEFAULT_PAGE_SIZE)

      render json: format_all_messages(messages)
    end
  end

  def sessions
    chats = current_user.chats
                        .joins(:messages)
                        .select("chats.*, MAX(messages.sent_at) as last_message_at, COUNT(messages.id) as message_count")
                        .group("chats.id")
                        .order("last_message_at DESC")

    render json: { sessions: format_sessions(chats) }
  end

  def destroy
    message = Message.joins(:chat)
                    .where(chats: { user_id: current_user.id })
                    .find(params[:id])
    message.destroy!

    render json: { message: "Message deleted successfully" }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Message not found" }, status: :not_found
  end

  def destroy_session
    result = @chat_service.destroy_session

    if result[:error]
      render json: result, status: :not_found
    else
      render json: result, status: :ok
    end
  rescue StandardError => e
    Rails.logger.error "Session deletion error: #{e.message}"
    render json: { error: "Failed to delete session" }, status: :internal_server_error
  end

  private

  def chat_params
    params.permit(:content, :session_id, :provider, :api_key, :system_prompt, :model, :temperature, :max_tokens)
  end

  def set_chat_service
    session_id = params[:session_id] || chat_params[:session_id]
    @chat_service = ChatMessageService.new(user: current_user, session_id: session_id)
  end

  def set_session_chat_service
    @chat_service = ChatMessageService.new(user: current_user, session_id: params[:id])
  end

  def format_all_messages(messages)
    {
      messages: messages.map { |msg| format_message(msg) },
      total_count: messages.total_count,
      current_page: messages.current_page,
      total_pages: messages.total_pages
    }
  end

  def format_message(message)
    session_id = extract_session_id(message.chat)

    {
      id: message.id,
      content: message.content,
      role: message.sender_kind == Message::SENDER_USER ? "user" : "assistant",
      session_id: session_id,
      metadata: message.llm_metadata,
      emotions: format_emotions(message),
      created_at: message.sent_at || message.created_at,
      updated_at: message.updated_at
    }
  end

  def extract_session_id(chat)
    if chat.title.start_with?("session:")
      chat.title.sub("session:", "")
    else
      "chat-#{chat.id}"
    end
  end

  def format_emotions(message)
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

  def format_sessions(chats)
    chats.map do |chat|
      session_id = extract_session_id(chat)
      user_messages = Message.where(chat: chat, sender: current_user)
      emotion_summary = analyze_session_emotions(user_messages)

      {
        session_id: session_id,
        chat_id: chat.id,
        last_message_at: chat.last_message_at,
        message_count: chat.message_count,
        preview: user_messages.first&.content&.truncate(100),
        emotions: emotion_summary
      }
    end
  end

  def analyze_session_emotions(messages)
    all_emotions = []

    messages.each do |msg|
      next unless msg.emotion_keywords.present?

      msg.emotion_keywords.each do |keyword|
        tag = emotion_tag(keyword)
        all_emotions << {
          name: keyword,
          label: tag ? tag.metadata["label_ja"] : keyword,
          intensity: msg.emotion_score || 0.5
        }
      end
    end

    aggregate_emotions(all_emotions)
  end

  def aggregate_emotions(emotions)
    return [] if emotions.empty?

    emotion_map = {}

    emotions.each do |emotion|
      next unless emotion.is_a?(Hash)

      name = emotion[:name]
      intensity = emotion[:intensity].to_f
      label = emotion[:label] || name

      if emotion_map[name]
        emotion_map[name][:count] += 1
        emotion_map[name][:total_intensity] += intensity
      else
        emotion_map[name] = {
          name: name,
          label: label,
          count: 1,
          total_intensity: intensity
        }
      end
    end

    # 上位3つの感情を返す
    emotion_map.values
              .map do |e|
                {
                  name: e[:name],
                  label: e[:label],
                  intensity: (e[:total_intensity] / e[:count]).round(2),
                  frequency: e[:count]
                }
              end
              .sort_by { |e| [ -e[:frequency], -e[:intensity] ] }
              .first(3)
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