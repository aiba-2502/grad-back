require "test_helper"

class MessageSenderKindTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123"
    )
    @chat = Chat.create!(
      user: @user,
      title: "Test Chat"
    )
  end

  test "should set sender_kind to USER for user messages" do
    message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "ユーザーからのメッセージ",
      sender_kind: "USER",
      sent_at: Time.current
    )

    assert_equal "USER", message.sender_kind
  end

  test "should set sender_kind to ASSISTANT for AI messages" do
    message = Message.create!(
      chat: @chat,
      sender: @user, # AIの場合もユーザーのコンテキストで保存
      content: "AIからの応答",
      sender_kind: "ASSISTANT",
      sent_at: Time.current
    )

    assert_equal "ASSISTANT", message.sender_kind
  end

  test "should validate presence of sender_kind" do
    message = Message.new(
      chat: @chat,
      sender: @user,
      content: "テストメッセージ",
      sent_at: Time.current
    )

    assert_not message.valid?
    assert_includes message.errors[:sender_kind], "can't be blank"
  end

  test "should validate inclusion of sender_kind values" do
    message = Message.new(
      chat: @chat,
      sender: @user,
      content: "テストメッセージ",
      sender_kind: "INVALID",
      sent_at: Time.current
    )

    assert_not message.valid?
    assert_includes message.errors[:sender_kind], "is not included in the list"
  end

  test "should have USER and ASSISTANT constants" do
    assert_equal "USER", Message::SENDER_USER
    assert_equal "ASSISTANT", Message::SENDER_ASSISTANT
  end

  test "should have scope for user messages" do
    user_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "ユーザーメッセージ",
      sender_kind: "USER",
      sent_at: Time.current
    )

    ai_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "AIメッセージ",
      sender_kind: "ASSISTANT",
      sent_at: Time.current
    )

    user_messages = Message.from_user
    assert_includes user_messages, user_message
    assert_not_includes user_messages, ai_message
  end

  test "should have scope for assistant messages" do
    user_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "ユーザーメッセージ",
      sender_kind: "USER",
      sent_at: Time.current
    )

    ai_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "AIメッセージ",
      sender_kind: "ASSISTANT",
      sent_at: Time.current
    )

    assistant_messages = Message.from_assistant
    assert_includes assistant_messages, ai_message
    assert_not_includes assistant_messages, user_message
  end

  test "should identify message type correctly" do
    user_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "ユーザーメッセージ",
      sender_kind: "USER",
      sent_at: Time.current
    )

    ai_message = Message.create!(
      chat: @chat,
      sender: @user,
      content: "AIメッセージ",
      sender_kind: "ASSISTANT",
      sent_at: Time.current
    )

    assert user_message.from_user?
    assert_not user_message.from_assistant?

    assert ai_message.from_assistant?
    assert_not ai_message.from_user?
  end
end
