require "test_helper"

class ApiTokenCurrentImplementationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )
  end

  test "should generate token pair with current implementation" do
    tokens = ApiToken.generate_token_pair(@user)

    assert_not_nil tokens[:access_token]
    assert_not_nil tokens[:refresh_token]

    # Current implementation returns OpenStruct with raw_token
    assert_not_nil tokens[:access_token].raw_token
    assert_not_nil tokens[:refresh_token].raw_token

    # Verify we can find the token by access token
    token_record = ApiToken.find_by_access_token(tokens[:access_token].raw_token)
    assert_not_nil token_record
    assert_equal @user.id, token_record.user_id

    # Verify we can find the token by refresh token
    token_record = ApiToken.find_by_refresh_token(tokens[:refresh_token].raw_token)
    assert_not_nil token_record
    assert_equal @user.id, token_record.user_id
  end

  test "should rotate tokens correctly" do
    tokens = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_refresh_token(tokens[:refresh_token].raw_token)

    new_tokens = token_record.rotate_tokens!

    assert_not_nil new_tokens[:access_token]
    assert_not_nil new_tokens[:refresh_token]
    assert_not_nil new_tokens[:access_token].raw_token
    assert_not_nil new_tokens[:refresh_token].raw_token

    # Old tokens should no longer work
    assert_nil ApiToken.find_by_access_token(tokens[:access_token].raw_token)
    assert_nil ApiToken.find_by_refresh_token(tokens[:refresh_token].raw_token)

    # New tokens should work
    assert_not_nil ApiToken.find_by_access_token(new_tokens[:access_token].raw_token)
    assert_not_nil ApiToken.find_by_refresh_token(new_tokens[:refresh_token].raw_token)
  end

  test "should validate access and refresh tokens correctly" do
    tokens = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_access_token(tokens[:access_token].raw_token)

    assert token_record.access_valid?
    assert token_record.refresh_valid?
    assert token_record.active?

    # Expire the access token
    token_record.update!(access_expires_at: 1.hour.ago)
    assert_not token_record.access_valid?
    assert token_record.refresh_valid? # Refresh should still be valid
    assert token_record.active? # Still active because refresh is valid

    # Expire the refresh token too
    token_record.update!(refresh_expires_at: 1.hour.ago)
    assert_not token_record.access_valid?
    assert_not token_record.refresh_valid?
    assert_not token_record.active? # Now inactive
  end

  test "should revoke entire token chain" do
    tokens = ApiToken.generate_token_pair(@user)
    token_record = ApiToken.find_by_access_token(tokens[:access_token].raw_token)

    # Rotate to create a chain
    new_tokens = token_record.rotate_tokens!

    # Revoke the chain
    token_record.revoke_chain!

    # Both current and any other tokens with same family_id should be revoked
    token_record.reload
    assert_not_nil token_record.revoked_at
    assert_not token_record.active?
  end
end
