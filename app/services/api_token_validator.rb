class ApiTokenValidator
  # トークンチェーンの再利用検知
  def self.detect_token_reuse(api_token)
    return false unless api_token.refresh? && api_token. token_family_id.present?

    # 同じチェーンIDで既に無効化されていないトークンが他に存在する場合
    reused_token = ApiToken.where(
       token_family_id: api_token. token_family_id,
      revoked_at: nil
    ).where.not(id: api_token.id).exists?

    if reused_token
      # セキュリティブリーチの可能性：チェーン全体を無効化
      ApiToken.where(token_family_id: api_token.token_family_id)
              .update_all(revoked_at: Time.current)
      return true
    end

    false
  end

  # レート制限チェック
  def self.rate_limit_exceeded?(user_id, limit: 10, window: 1.minute)
    recent_attempts = ApiToken.where(
      user_id: user_id,
      created_at: window.ago..Time.current
    ).count

    recent_attempts > limit
  end
end
