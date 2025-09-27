require "test_helper"
require "minitest/mock"

class ChatMessageServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123"
    )
    @session_id = SecureRandom.uuid
    @service = ChatMessageService.new(user: @user, session_id: @session_id)
  end

  test "initializes with user and session_id" do
    assert_equal @user, @service.user
    assert_not_nil @service.chat
    assert @service.chat.title.include?(@session_id)
  end

  test "generates session_id when not provided" do
    service = ChatMessageService.new(user: @user)
    assert_not_nil service.chat
    assert service.chat.title.start_with?("session:")
  end

  test "creates message with emotion extraction" do
    # Mock the AI services
    mock_ai_service = Minitest::Mock.new
    mock_ai_service.expect(:chat, {
      "content" => "AI response",
      "model" => "gpt-3.5-turbo",
      "provider" => "openai"
    }) do |messages, options|
      messages.is_a?(Array) && options.is_a?(Hash)
    end

    AiServiceV2.stub :new, mock_ai_service do
      result = @service.create_message(
        content: "テストメッセージです。嬉しいです。",
        provider: "openai",
        api_key: nil
      )

      assert_not_nil result[:session_id]
      assert_not_nil result[:chat_id]
      assert_not_nil result[:user_message]
      assert_not_nil result[:assistant_message]

      # Check user message
      assert_equal "テストメッセージです。嬉しいです。", result[:user_message][:content]
      assert_equal "user", result[:user_message][:role]

      # Check assistant message
      assert_equal "AI response", result[:assistant_message][:content]
      assert_equal "assistant", result[:assistant_message][:role]
    end

    # Verify messages were saved to database
    messages = Message.where(chat: @service.chat).order(sent_at: :asc)
    assert_equal 2, messages.count
    assert_equal Message::SENDER_USER, messages.first.sender_kind
    assert_equal Message::SENDER_ASSISTANT, messages.last.sender_kind
  end

  test "list_messages returns paginated results" do
    # Create some test messages
    5.times do |i|
      Message.create!(
        chat: @service.chat,
        sender: @user,
        content: "Message #{i}",
        sender_kind: i.even? ? Message::SENDER_USER : Message::SENDER_ASSISTANT,
        sent_at: i.hours.ago
      )
    end

    result = @service.list_messages(page: 1, per_page: 3)

    assert_equal 3, result[:messages].size
    assert_equal 5, result[:total_count]
    assert_equal 1, result[:current_page]
    assert_equal 2, result[:total_pages]
  end

  test "destroy_session deletes chat and messages" do
    # Create some messages
    3.times do
      Message.create!(
        chat: @service.chat,
        sender: @user,
        content: "Test message",
        sender_kind: Message::SENDER_USER,
        sent_at: Time.current
      )
    end

    result = @service.destroy_session

    assert_equal "セッションを正常に削除しました", result[:message]
    assert_equal 3, result[:deleted_count]

    # Verify chat and messages are deleted
    assert_nil Chat.find_by(id: @service.chat.id)
    assert_empty Message.where(chat: @service.chat)
  end

  test "handles emotion extraction failure gracefully" do
    # Mock AI service to fail for emotion extraction but succeed for chat
    mock_ai_service = Minitest::Mock.new
    mock_ai_service.expect(:chat, {
      "content" => "AI response",
      "model" => "gpt-3.5-turbo",
      "provider" => "openai"
    }) do |messages, options|
      messages.is_a?(Array) && options.is_a?(Hash)
    end

    # Mock emotion service to raise error
    mock_emotion_service = Minitest::Mock.new
    def mock_emotion_service.extract_emotions(text)
      raise StandardError.new("API Error")
    end

    EmotionExtractionService.stub :new, mock_emotion_service do
      AiServiceV2.stub :new, mock_ai_service do
        result = @service.create_message(
          content: "テストメッセージ",
          provider: "openai"
        )

        # Should still create message despite emotion extraction failure
        assert_not_nil result[:user_message]
        assert_empty result[:user_message][:emotions] || []
      end
    end
  end

  test "applies dynamic prompt when not provided" do
    # Create past messages
    Message.create!(
      chat: @service.chat,
      sender: @user,
      content: "前のメッセージ",
      sender_kind: Message::SENDER_USER,
      sent_at: 1.hour.ago,
      emotion_keywords: ["joy"],
      emotion_score: 0.8
    )

    mock_ai_service = Minitest::Mock.new
    mock_ai_service.expect(:chat, {
      "content" => "AI response",
      "model" => "gpt-3.5-turbo",
      "provider" => "openai"
    }) do |messages, options|
      messages.is_a?(Array) && options.is_a?(Hash)
    end

    mock_prompt_service = Minitest::Mock.new
    mock_prompt_service.expect(:generate_system_prompt, "Dynamic prompt")
    mock_prompt_service.expect(:recommended_temperature, 0.8)

    DynamicPromptService.stub :new, mock_prompt_service do
      AiServiceV2.stub :new, mock_ai_service do
        result = @service.create_message(
          content: "新しいメッセージ",
          provider: "openai",
          system_prompt: nil  # Not provided, should use dynamic
        )

        assert_not_nil result[:assistant_message]
      end
    end
  end

  test "uses provided system prompt and temperature" do
    mock_ai_service = Minitest::Mock.new

    # Capture the arguments passed to chat method
    mock_ai_service.expect(:chat, {
      "content" => "AI response",
      "model" => "custom-model",
      "provider" => "anthropic"
    }) do |messages, options|
      # Verify system prompt is included
      assert messages.first[:role] == "system"
      assert messages.first[:content] == "Custom prompt"
      # Verify temperature
      assert_equal 0.5, options[:temperature]
      true
    end

    AiServiceV2.stub :new, mock_ai_service do
      result = @service.create_message(
        content: "Test",
        provider: "anthropic",
        system_prompt: "Custom prompt",
        model: "custom-model",
        temperature: 0.5,
        max_tokens: 1000
      )

      assert_not_nil result
    end
  end
end