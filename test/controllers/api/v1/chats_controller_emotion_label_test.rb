require "test_helper"

class Api::V1::ChatsControllerEmotionLabelTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123"
    )

    # 感情タグをセットアップ
    Tag.create!(
      name: "joy",
      category: "emotion",
      metadata: {
        label_ja: "喜び",
        label_en: "Joy",
        color: "#FFD700",
        intensity_default: 0.5
      },
      is_active: true
    )

    Tag.create!(
      name: "sadness",
      category: "emotion",
      metadata: {
        label_ja: "悲しみ",
        label_en: "Sadness",
        color: "#4169E1",
        intensity_default: 0.5
      },
      is_active: true
    )

    # APIトークン生成
    raw_token = SecureRandom.hex(32)
    api_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(raw_token),
      access_expires_at: 1.hour.from_now
    )
    @token = raw_token
  end

  test "should return Japanese emotion labels in index response" do
    # チャットとメッセージを作成
    chat = Chat.create!(
      user: @user,
      title: "session:test-session"
    )

    Message.create!(
      chat: chat,
      sender: @user,
      content: "テストメッセージ",
      sender_kind: Message::SENDER_USER,
      emotion_keywords: [ "joy", "sadness" ],
      emotion_score: 0.7,
      sent_at: Time.current
    )

    # index APIを呼び出し
    get api_v1_chats_path,
      params: { session_id: "test-session" },
      headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success

    result = JSON.parse(response.body)
    assert_not_nil result["messages"]
    assert result["messages"].length > 0

    message = result["messages"].first
    assert_not_nil message["emotions"]

    # 日本語ラベルが返されることを確認
    emotions = message["emotions"]
    emotion_labels = emotions.map { |e| e["label"] }

    assert_includes emotion_labels, "喜び"
    assert_includes emotion_labels, "悲しみ"
    assert_not_includes emotion_labels, "joy"
    assert_not_includes emotion_labels, "sadness"
  end

  test "should return Japanese emotion labels in sessions response" do
    # チャットとメッセージを作成
    chat = Chat.create!(
      user: @user,
      title: "session:test-session"
    )

    Message.create!(
      chat: chat,
      sender: @user,
      content: "嬉しいメッセージ",
      sender_kind: Message::SENDER_USER,
      emotion_keywords: [ "joy" ],
      emotion_score: 0.8,
      sent_at: Time.current
    )

    Message.create!(
      chat: chat,
      sender: @user,
      content: "悲しいメッセージ",
      sender_kind: Message::SENDER_USER,
      emotion_keywords: [ "sadness" ],
      emotion_score: 0.6,
      sent_at: Time.current
    )

    # sessions APIを呼び出し
    get sessions_api_v1_chats_path,
      headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success

    result = JSON.parse(response.body)
    assert_not_nil result["sessions"]
    assert result["sessions"].length > 0

    session = result["sessions"].first
    assert_not_nil session["emotions"]

    # 日本語ラベルが返されることを確認
    emotions = session["emotions"]
    emotion_labels = emotions.map { |e| e["label"] }

    # どちらかの感情が含まれている
    assert (emotion_labels.include?("喜び") || emotion_labels.include?("悲しみ"))
    assert_not emotion_labels.any? { |label| label == "joy" || label == "sadness" }
  end

  test "should handle missing emotion tags gracefully" do
    # チャットとメッセージを作成（存在しない感情タグ）
    chat = Chat.create!(
      user: @user,
      title: "session:test-session"
    )

    Message.create!(
      chat: chat,
      sender: @user,
      content: "テストメッセージ",
      sender_kind: Message::SENDER_USER,
      emotion_keywords: [ "unknown_emotion" ],
      emotion_score: 0.5,
      sent_at: Time.current
    )

    # index APIを呼び出し
    get api_v1_chats_path,
      params: { session_id: "test-session" },
      headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success

    result = JSON.parse(response.body)
    message = result["messages"].first
    emotions = message["emotions"]

    # 存在しない感情タグの場合、英語名がそのままラベルになる
    assert_equal "unknown_emotion", emotions.first["label"]
  end
end
