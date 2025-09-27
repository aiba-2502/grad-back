require "test_helper"

class ApiTokenSingleRecordTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "single_record_test_#{SecureRandom.hex(8)}@example.com",
      password: "password123",
      name: "Test User"
    )
  end

  # 1レコードでトークンペアを管理
  test "should generate token pair in single record" do
    result = ApiToken.generate_token_pair(@user)

    # 返り値の確認
    assert_not_nil result[:access_token].raw_token
    assert_not_nil result[:refresh_token].raw_token
    assert result[:access_token].raw_token != result[:refresh_token].raw_token

    # データベースに1レコードのみ作成されることを確認
    assert_equal 1, ApiToken.where(user: @user).count

    # レコード内容の確認
    token_record = ApiToken.last
    assert_equal @user, token_record.user
    assert_not_nil token_record.encrypted_access_token
    assert_not_nil token_record.encrypted_refresh_token
    assert_not_nil token_record.access_expires_at
    assert_not_nil token_record.refresh_expires_at
    assert_not_nil token_record. token_family_id

    # 暗号化されたトークンが異なることを確認
    assert token_record.encrypted_access_token != token_record.encrypted_refresh_token
  end

  # アクセストークンでの検索
  test "should find by access token" do
    result = ApiToken.generate_token_pair(@user)
    access_token_value = result[:access_token].raw_token

    found_token = ApiToken.find_by_access_token(access_token_value)
    assert_not_nil found_token
    assert_equal @user, found_token.user
  end

  # リフレッシュトークンでの検索
  test "should find by refresh token" do
    result = ApiToken.generate_token_pair(@user)
    refresh_token_value = result[:refresh_token].raw_token

    found_token = ApiToken.find_by_refresh_token(refresh_token_value)
    assert_not_nil found_token
    assert_equal @user, found_token.user
  end

  # トークンローテーション（同一レコード更新）
  test "should rotate tokens on same record" do
    result = ApiToken.generate_token_pair(@user)
    original_access = result[:access_token].raw_token
    original_refresh = result[:refresh_token].raw_token

    token_record = ApiToken.find_by_refresh_token(original_refresh)
    original_id = token_record.id
    original_family_id = token_record. token_family_id

    # トークンをローテーション
    new_tokens = token_record.rotate_tokens!

    # 新しいトークンが生成されることを確認
    assert_not_equal original_access, new_tokens[:access_token].raw_token
    assert_not_equal original_refresh, new_tokens[:refresh_token].raw_token

    # 同じレコードが更新されることを確認
    token_record.reload
    assert_equal original_id, token_record.id
    assert_equal original_family_id, token_record. token_family_id

    # レコード数が増えないことを確認
    assert_equal 1, ApiToken.where(user: @user).count

    # 新しいトークンで検索できることを確認
    assert_not_nil ApiToken.find_by_access_token(new_tokens[:access_token].raw_token)
    assert_not_nil ApiToken.find_by_refresh_token(new_tokens[:refresh_token].raw_token)

    # 古いトークンでは検索できないことを確認
    assert_nil ApiToken.find_by_access_token(original_access)
    assert_nil ApiToken.find_by_refresh_token(original_refresh)
  end

  # アクセストークンの有効期限
  test "should validate access token expiry" do
    result = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_access_token(result[:access_token].raw_token)

    # 有効な状態
    assert token_record.access_valid?

    # 期限切れに設定
    token_record.update!(access_expires_at: 1.hour.ago)
    assert_not token_record.access_valid?

    # リフレッシュトークンは有効なままであることを確認
    assert token_record.refresh_valid?
    assert token_record.active?
  end

  # リフレッシュトークンの有効期限
  test "should validate refresh token expiry" do
    result = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_refresh_token(result[:refresh_token].raw_token)

    # 有効な状態
    assert token_record.refresh_valid?

    # 期限切れに設定
    token_record.update!(refresh_expires_at: 1.day.ago)
    assert_not token_record.refresh_valid?

    # アクセストークンは有効なままであることを確認
    assert token_record.access_valid?
    assert token_record.active?
  end

  # 両方のトークンが期限切れ
  test "should be inactive when both tokens expired" do
    result = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_access_token(result[:access_token].raw_token)

    token_record.update!(
      access_expires_at: 1.hour.ago,
      refresh_expires_at: 1.day.ago
    )

    assert_not token_record.access_valid?
    assert_not token_record.refresh_valid?
    assert_not token_record.active?
    assert token_record.expired?
  end

  # トークンチェーンの無効化
  test "should revoke entire token chain" do
     token_family_id = SecureRandom.uuid

    # 同じchain_idで複数のトークンレコードを作成
    token1 = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token("token1_access"),
      encrypted_refresh_token: ApiToken.encrypt_token("token1_refresh"),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
       token_family_id:  token_family_id
    )

    token2 = ApiToken.create!(
      user: @user,
      encrypted_access_token: ApiToken.encrypt_token("token2_access"),
      encrypted_refresh_token: ApiToken.encrypt_token("token2_refresh"),
      access_expires_at: 2.hours.from_now,
      refresh_expires_at: 7.days.from_now,
       token_family_id:  token_family_id
    )

    # チェーンを無効化
    token1.revoke_chain!

    # 両方のトークンが無効化されることを確認
    token1.reload
    token2.reload
    assert_not_nil token1.revoked_at
    assert_not_nil token2.revoked_at
    assert_not token1.active?
    assert_not token2.active?
  end

  # 後方互換性：find_by_tokenメソッド
  test "should maintain backward compatibility with find_by_token" do
    result = ApiToken.generate_token_pair(@user)

    # アクセストークンで検索（従来のfind_by_tokenメソッド）
    found = ApiToken.find_by_token(result[:access_token].raw_token)
    assert_not_nil found
    assert_equal @user, found.user

    # リフレッシュトークンで検索（従来のfind_by_tokenメソッド）
    found = ApiToken.find_by_token(result[:refresh_token].raw_token)
    assert_not_nil found
    assert_equal @user, found.user
  end

  # クリーンアップ機能
  test "should cleanup old tokens" do
    # 複数のトークンレコードを作成
    6.times do
      ApiToken.generate_token_pair(@user)
    end

    assert_equal 6, ApiToken.where(user: @user).count

    # 古いトークンをクリーンアップ（最新5つを保持）
    ApiToken.cleanup_old_tokens(@user.id, keep_count: 5)

    # アクティブなトークンが5つだけ残ることを確認
    assert_equal 5, ApiToken.where(user: @user, revoked_at: nil).count
    assert_equal 6, ApiToken.where(user: @user).count # 総数は変わらない
  end
end
