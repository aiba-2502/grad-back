class JsonWebToken
  # トークンの有効期限定数
  DEFAULT_EXPIRATION = 24.hours

  # 環境変数からシークレットキーを取得
  SECRET_KEY = ENV.fetch("JWT_SECRET_KEY") do
    Rails.application.credentials.secret_key_base ||
    Rails.application.secret_key_base
  end

  def self.encode(payload, exp = DEFAULT_EXPIRATION.from_now)
    payload[:exp] = exp.to_i
    JWT.encode(payload, SECRET_KEY)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY)[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::ExpiredSignature => e
    Rails.logger.error "JWT expired: #{e.message}"
    nil
  rescue JWT::DecodeError => e
    Rails.logger.error "JWT decode error: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "Unexpected error in JsonWebToken.decode: #{e.message}"
    nil
  end
end
