require "test_helper"

class ApiTokenValidatorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )
  end

  # トークン再利用検知のテスト
  test "should detect token reuse" do
    token_family_id = SecureRandom.uuid

    # 有効なリフレッシュトークン
    valid_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )

    # 同じチェーンIDの別のトークン（無効化されていない）
    another_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )

    # トークン再利用を検知
    assert ApiTokenValidator.detect_token_reuse(valid_token)

    # チェーン全体が無効化されることを確認
    valid_token.reload
    another_token.reload
    assert_not_nil valid_token.revoked_at
    assert_not_nil another_token.revoked_at
  end

  test "should not detect reuse for single token in chain" do
    token_family_id = SecureRandom.uuid

    token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )

    # 単一トークンの場合は再利用検知しない
    assert_not ApiTokenValidator.detect_token_reuse(token)
  end

  test "should not detect reuse for access tokens" do
    token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now
    )

    # アクセストークンは再利用検知の対象外
    assert_not ApiTokenValidator.detect_token_reuse(token)
  end

  # レート制限のテスト
  test "should detect rate limit exceeded" do
    # 制限内のトークン作成
    5.times do
      ApiToken.create!(
        user: @user,
        encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        access_expires_at: 2.hours.from_now,
        refresh_expires_at: 7.days.from_now
      )
    end

    # レート制限内
    assert_not ApiTokenValidator.rate_limit_exceeded?(@user.id, limit: 10)

    # さらに6つ作成して制限超過
    6.times do
      ApiToken.create!(
        user: @user,
        encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        access_expires_at: 2.hours.from_now,
        refresh_expires_at: 7.days.from_now
      )
    end

    # レート制限超過
    assert ApiTokenValidator.rate_limit_exceeded?(@user.id, limit: 10)
  end

  test "should check rate limit within time window" do
    # 2分前のトークン（ウィンドウ外）
    old_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      created_at: 2.minutes.ago
    )

    # 30秒前のトークン（ウィンドウ内）
    recent_tokens = 3.times.map do
      ApiToken.create!(
        user: @user,
        encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        access_expires_at: 2.hours.from_now,
        refresh_expires_at: 7.days.from_now,
        created_at: 30.seconds.ago
      )
    end

    # 1分以内のトークンのみカウント
    assert_not ApiTokenValidator.rate_limit_exceeded?(@user.id, limit: 5, window: 1.minute)
  end

  test "should allow custom rate limit parameters" do
    # 5秒以内に3つ作成
    3.times do
      ApiToken.create!(
        user: @user,
        encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        access_expires_at: 2.hours.from_now,
        refresh_expires_at: 7.days.from_now
      )
    end

    # カスタム制限（5秒以内に2つまで）で超過
    assert ApiTokenValidator.rate_limit_exceeded?(@user.id, limit: 2, window: 5.seconds)

    # デフォルト制限では問題なし
    assert_not ApiTokenValidator.rate_limit_exceeded?(@user.id)
  end
end
