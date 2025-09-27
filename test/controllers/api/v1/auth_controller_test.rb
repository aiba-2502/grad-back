require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )
  end

  # ログインエンドポイントのテスト
  test "should login with valid credentials" do
    post api_v1_login_url, params: {
      email: "test@example.com",
      password: "password123"
    }, as: :json

    assert_response :success

    json_response = JSON.parse(@response.body)
    assert_not_nil json_response["access_token"]
    assert_not_nil json_response["refresh_token"]
    assert_equal @user.id, json_response["user"]["id"]
    assert_equal @user.email, json_response["user"]["email"]
  end

  test "should not login with invalid credentials" do
    post api_v1_login_url, params: {
      email: "test@example.com",
      password: "wrongpassword"
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "メールアドレスまたはパスワードが不正です", json_response["error"]
  end

  test "should not login with non-existent user" do
    post api_v1_login_url, params: {
      email: "nonexistent@example.com",
      password: "password123"
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "メールアドレスまたはパスワードが不正です", json_response["error"]
  end

  # 新規登録エンドポイントのテスト
  test "should signup with valid parameters" do
    post api_v1_signup_url, params: {
      name: "New User",
      email: "newuser@example.com",
      password: "password123"
    }, as: :json

    assert_response :created

    json_response = JSON.parse(@response.body)
    assert_not_nil json_response["access_token"]
    assert_not_nil json_response["refresh_token"]
    assert_equal "newuser@example.com", json_response["user"]["email"]
    assert_equal "New User", json_response["user"]["name"]
  end

  test "should set authentication cookies after signup" do
    post api_v1_signup_url, params: {
      name: "Cookie User",
      email: "cookieuser@example.com",
      password: "password123"
    }, as: :json

    assert_response :created

    # HTTP-onlyクッキーが設定されていることを確認
    assert_not_nil @response.cookies["access_token"]
    assert_not_nil @response.cookies["refresh_token"]

    # APIレスポンスにもトークンが含まれることを確認
    json_response = JSON.parse(@response.body)
    assert_not_nil json_response["access_token"]
    assert_not_nil json_response["refresh_token"]
  end

  test "should not signup with invalid email" do
    post api_v1_signup_url, params: {
      name: "Invalid User",
      email: "invalid-email",
      password: "password123"
    }, as: :json

    assert_response :unprocessable_entity

    json_response = JSON.parse(@response.body)
    assert_includes json_response["errors"].join, "Email"
  end

  test "should not signup with duplicate email" do
    post api_v1_signup_url, params: {
      name: "Duplicate User",
      email: "test@example.com",  # 既存のユーザーのメール
      password: "password123"
    }, as: :json

    assert_response :unprocessable_entity

    json_response = JSON.parse(@response.body)
    assert_includes json_response["errors"].join, "Email has already been taken"
  end

  # リフレッシュエンドポイントのテスト
  test "should refresh tokens with valid refresh token" do
    tokens = ApiToken.generate_token_pair(@user)
    refresh_token = tokens[:refresh_token]

    post api_v1_refresh_url, params: {
      refresh_token: refresh_token.raw_token
    }, as: :json

    assert_response :success

    json_response = JSON.parse(@response.body)
    assert_not_nil json_response["access_token"]
    assert_not_nil json_response["refresh_token"]

    # 古いリフレッシュトークンが無効化されていることを確認
    refresh_token.reload
    assert_not_nil refresh_token.revoked_at
  end

  test "should not refresh with expired refresh token" do
    raw_refresh_token = SecureRandom.hex(32)
    refresh_token = ApiToken.create!(
      user: @user,
      encrypted_refresh_token: ApiToken.encrypt_token(raw_refresh_token),
      refresh_expires_at: 1.hour.ago
    )
    refresh_token.raw_refresh_token = raw_refresh_token

    post api_v1_refresh_url, params: {
      refresh_token: raw_refresh_token
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "無効または期限切れのリフレッシュトークンです", json_response["error"]
  end

  test "should not refresh with revoked refresh token" do
    raw_refresh_token = SecureRandom.hex(32)
    refresh_token = ApiToken.create!(
      user: @user,
      encrypted_refresh_token: ApiToken.encrypt_token(raw_refresh_token),
      refresh_expires_at: 7.days.from_now,
      revoked_at: Time.current
    )
    refresh_token.raw_refresh_token = raw_refresh_token

    post api_v1_refresh_url, params: {
      refresh_token: raw_refresh_token
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    # 無効化されたトークンはトークン再利用として検知される
    assert_equal "トークンの再利用が検出されました", json_response["error"]
  end

  test "should detect token reuse and revoke chain" do
    token_family_id = SecureRandom.uuid

    # 最初のリフレッシュトークン
    raw_refresh_token = SecureRandom.hex(32)
    original_token = ApiToken.create!(
      user: @user,
      encrypted_refresh_token: ApiToken.encrypt_token(raw_refresh_token),
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )
    original_token.raw_refresh_token = raw_refresh_token

    # トークンをリフレッシュ（新しいトークンが生成される）
    post api_v1_refresh_url, params: {
      refresh_token: original_token.raw_refresh_token
    }, as: :json

    assert_response :success

    # 古いトークンを再利用しようとする（トークン再利用攻撃）
    post api_v1_refresh_url, params: {
      refresh_token: original_token.raw_refresh_token
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "トークンの再利用が検出されました", json_response["error"]

    # チェーン全体が無効化されていることを確認
    ApiToken.where(token_family_id: token_family_id).each do |token|
      token.reload
      assert_not_nil token.revoked_at
    end
  end

  # ログアウトエンドポイントのテスト
  test "should logout with valid access token" do
    tokens = ApiToken.generate_token_pair(@user)
    access_token = tokens[:access_token]

    post api_v1_logout_url, headers: {
      "Authorization" => "Bearer #{access_token.raw_token}"
    }, as: :json

    assert_response :success

    json_response = JSON.parse(@response.body)
    assert_equal "正常にログアウトしました", json_response["message"]

    # アクセストークンが無効化されていることを確認
    access_token.reload
    assert_not_nil access_token.revoked_at

    # 同じチェーンのリフレッシュトークンも無効化されていることを確認
    if tokens[:refresh_token]. token_family_id.present?
      tokens[:refresh_token].reload
      assert_not_nil tokens[:refresh_token].revoked_at
    end
  end

  test "should not logout with invalid access token" do
    post api_v1_logout_url, headers: {
      "Authorization" => "Bearer invalid_token"
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "無効または期限切れのトークンです", json_response["error"]
  end

  test "should not logout without access token" do
    post api_v1_logout_url, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "認証ヘッダーが必要です", json_response["error"]
  end

  # 現在のユーザー情報取得のテスト
  test "should get current user with valid access token" do
    tokens = ApiToken.generate_token_pair(@user)
    access_token = tokens[:access_token]

    get api_v1_me_url, headers: {
      "Authorization" => "Bearer #{access_token.raw_token}"
    }, as: :json

    assert_response :success

    json_response = JSON.parse(@response.body)
    assert_equal @user.id, json_response["id"]
    assert_equal @user.email, json_response["email"]
    assert_equal @user.name, json_response["name"]
  end

  test "should not get current user with expired access token" do
    raw_access_token = SecureRandom.hex(32)
    raw_refresh_token = SecureRandom.hex(32)
    access_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(raw_access_token),
      encrypted_refresh_token: ApiToken.encrypt_token(raw_refresh_token),
      access_expires_at: 1.hour.ago,
      refresh_expires_at: 7.days.from_now
    )
    access_token.raw_access_token = raw_access_token

    get api_v1_me_url, headers: {
      "Authorization" => "Bearer #{access_token.raw_access_token}"
    }, as: :json

    assert_response :unauthorized

    json_response = JSON.parse(@response.body)
    assert_equal "無効または期限切れのトークンです", json_response["error"]
  end

  # レート制限のテスト
  test "should enforce rate limiting on login attempts" do
    # テスト用にメモリストアキャッシュを有効化
    original_cache_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      # 11回ログイン試行（制限は10回）
      11.times do |i|
        post api_v1_login_url, params: {
          email: "test@example.com",
          password: "wrongpassword#{i}"
        }, as: :json
      end

      assert_response :too_many_requests

      json_response = JSON.parse(@response.body)
      assert_equal "リクエストが多すぎます。しばらくしてからお試しください。", json_response["error"]
    ensure
      # 元のキャッシュストアに戻す
      Rails.cache = original_cache_store
    end
  end
end
