require "test_helper"

class Api::V1::ChatsControllerCreateTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123"
    )

    # ApiTokenを使用した認証
    tokens = ApiToken.generate_token_pair(@user)
    @token = tokens[:access_token].raw_token
  end

  test "should create chat message without ChatSessionService" do
    session_id = SecureRandom.uuid

    # ChatSessionServiceが削除されていても正常に動作することを確認
    assert_raises(NameError) { ChatSessionService }

    # APIリクエスト
    post api_v1_chats_path,
      params: {
        content: "テストメッセージです",
        session_id: session_id,
        provider: "openai"
      },
      headers: {
        "Authorization" => "Bearer #{@token}"
      }

    # レスポンスの確認
    assert_response :success

    result = JSON.parse(response.body)
    assert_not_nil result["session_id"]
    assert_not_nil result["chat_id"]
    assert_not_nil result["user_message"]

    # データベースの確認
    chat = Chat.find_by(title: "session:#{session_id}", user: @user)
    assert_not_nil chat
    assert_equal 2, chat.messages.count  # User message and assistant message

    user_message = chat.messages.find_by(sender_kind: Message::SENDER_USER)
    assert_not_nil user_message
    assert_equal "テストメッセージです", user_message.content
    assert_equal @user.id, user_message.sender_id

    assistant_message = chat.messages.find_by(sender_kind: Message::SENDER_ASSISTANT)
    assert_not_nil assistant_message
  end

  test "should find existing chat for same session_id" do
    session_id = SecureRandom.uuid

    # 既存のチャットを作成
    existing_chat = Chat.create!(
      user: @user,
      title: "session:#{session_id}"
    )

    # APIリクエスト
    post api_v1_chats_path,
      params: {
        content: "既存セッションへのメッセージ",
        session_id: session_id,
        provider: "openai"
      },
      headers: {
        "Authorization" => "Bearer #{@token}"
      }

    assert_response :success

    result = JSON.parse(response.body)
    assert_equal session_id, result["session_id"]
    assert_equal existing_chat.id, result["chat_id"]

    # 同じチャットが使用されることを確認
    assert_equal 1, Chat.where(title: "session:#{session_id}").count
  end

  test "should generate session_id if not provided" do
    # session_idなしでリクエスト
    post api_v1_chats_path,
      params: {
        content: "session_idなしのメッセージ",
        provider: "openai"
      },
      headers: {
        "Authorization" => "Bearer #{@token}"
      }

    assert_response :success

    result = JSON.parse(response.body)
    assert_not_nil result["session_id"]
    assert_not_nil result["chat_id"]

    # 生成されたsession_idでチャットが作成されることを確認
    chat = Chat.find(result["chat_id"])
    assert_equal "session:#{result['session_id']}", chat.title
  end
end
