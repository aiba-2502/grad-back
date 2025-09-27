require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )
  end

  # トークンペア生成のテスト
  test "should generate token pair with access and refresh tokens" do
    tokens = ApiToken.generate_token_pair(@user)

    assert_not_nil tokens[:access_token]
    assert_not_nil tokens[:refresh_token]

    # Current implementation returns OpenStruct with raw_token
    assert_not_nil tokens[:access_token].raw_token
    assert_not_nil tokens[:refresh_token].raw_token

    # Verify tokens are stored in database
    token_record = ApiToken.find_by_access_token(tokens[:access_token].raw_token)
    assert_not_nil token_record
    assert_not_nil token_record.token_family_id

    # アクセストークンは2時間後に期限切れ
    assert_in_delta 2.hours.from_now.to_i, token_record.access_expires_at.to_i, 5

    # リフレッシュトークンは7日後に期限切れ
    assert_in_delta 7.days.from_now.to_i, token_record.refresh_expires_at.to_i, 5
  end

  # トークン検証のテスト
  test "should validate token correctly" do
    raw_access = SecureRandom.hex(32)
    raw_refresh = SecureRandom.hex(32)

    token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(raw_access),
      encrypted_refresh_token: ApiToken.encrypt_token(raw_refresh),
      access_expires_at: 1.hour.from_now,
      refresh_expires_at: 7.days.from_now
    )

    assert token.token_valid?
    assert token.access_valid?

    # 期限切れトークンは無効
    expired_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 1.hour.ago,
      refresh_expires_at: 1.hour.ago
    )

    assert_not expired_token.token_valid?

    # 無効化されたトークンは無効
    revoked_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 1.hour.from_now,
      refresh_expires_at: 7.days.from_now,
      revoked_at: Time.current
    )

    assert_not revoked_token.token_valid?
  end

  # トークンチェーン無効化のテスト
  test "should revoke entire token chain" do
    token_family_id = SecureRandom.uuid

    token1 = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )

    token2 = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
      token_family_id: token_family_id
    )

    # チェーン全体を無効化
    token1.revoke_chain!

    token1.reload
    token2.reload

    assert_not_nil token1.revoked_at
    assert_not_nil token2.revoked_at
  end

  # スコープのテスト
  test "should filter tokens by scope" do
    # アクティブなトークン
    active_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 1.hour.from_now,
      refresh_expires_at: 7.days.from_now
    )

    # 期限切れトークン
    expired_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 1.hour.ago,
      refresh_expires_at: 1.hour.ago
    )

    # 無効化されたトークン
    revoked_token = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
      access_expires_at: 1.hour.from_now,
      refresh_expires_at: 7.days.from_now,
      revoked_at: Time.current
    )

    # activeスコープのテスト
    active_tokens = ApiToken.active
    assert_includes active_tokens, active_token
    assert_not_includes active_tokens, expired_token
    assert_not_includes active_tokens, revoked_token

    # expiredスコープのテスト
    expired_tokens = ApiToken.expired
    assert_includes expired_tokens, expired_token
    assert_not_includes expired_tokens, active_token
    assert_not_includes expired_tokens, revoked_token
  end

  # クリーンアップのテスト
  test "should cleanup old tokens keeping only recent ones" do
    # 6つのトークンを作成
    6.times do |i|
      ApiToken.create!(
        user: @user,
        encrypted_access_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        encrypted_refresh_token: ApiToken.encrypt_token(SecureRandom.hex(32)),
        access_expires_at: 2.hours.from_now,
        refresh_expires_at: 7.days.from_now,
        created_at: i.hours.ago
      )
    end

    assert_equal 6, ApiToken.where(user: @user).count

    # 最新5つのみ保持
    ApiToken.cleanup_old_tokens(@user.id, keep_count: 5)

    active_tokens = ApiToken.where(user: @user, revoked_at: nil)
    assert_equal 5, active_tokens.count

    # 最も古いトークンが無効化されていることを確認
    oldest_token = ApiToken.where(user: @user).order(created_at: :asc).first
    assert_not_nil oldest_token.revoked_at
  end

  # セキュアトークン生成のテスト
  test "should generate secure token" do
    token1 = SecureRandom.hex(32)
    token2 = SecureRandom.hex(32)

    # トークンは毎回異なる
    assert_not_equal token1, token2

    # 適切な長さ
    assert_equal 64, token1.length # Hexエンコードされた32バイト
  end
end
