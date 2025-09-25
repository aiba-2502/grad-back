class ApplicationController < ActionController::API
  include ActionController::Cookies
  attr_reader :current_user

  # ApiTokenベースの認証メソッド
  def authenticate_user!
    token_value = extract_token_from_header

    unless token_value
      return render json: { error: "認証ヘッダーが必要です" }, status: :unauthorized
    end

    access_token = ApiToken.find_by_token(token_value)

    if access_token.nil? || !access_token.access? || !access_token.token_valid?
      return render json: { error: "無効または期限切れのトークンです" }, status: :unauthorized
    end

    @current_user = access_token.user
  end

  def extract_token_from_header
    request.headers["Authorization"]&.split(" ")&.last
  end

  # JWTベースの認証メソッド（後方互換性のため残す）
  def authorize_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    # デバッグログは開発環境のみ
    Rails.logger.debug "認証試行" if Rails.env.development?

    unless header
      render json: { errors: "認証ヘッダーがありません" }, status: :unauthorized
      return
    end

    decoded = JsonWebToken.decode(header)

    unless decoded
      render json: { errors: "無効なトークンです" }, status: :unauthorized
      return
    end

    @current_user = User.find(decoded[:user_id])
    # ユーザーIDのみログ出力（個人情報は出力しない）
    Rails.logger.info "ユーザー認証成功: ID #{@current_user.id}" if Rails.env.development?
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "認証用ユーザーが見つかりません"
    render json: { errors: "ユーザーが見つかりません" }, status: :unauthorized
  rescue JWT::DecodeError => e
    Rails.logger.error "JWTデコードエラーが発生しました"
    render json: { errors: "トークン形式が不正です" }, status: :unauthorized
  rescue StandardError => e
    Rails.logger.error "認証失敗: #{e.class.name}"
    render json: { errors: "認証が失敗しました" }, status: :unauthorized
  end
end
