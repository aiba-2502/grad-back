module Api
  module V1
    class AuthController < ApplicationController
      before_action :authenticate_user!, only: [ :me, :logout ]
      before_action :check_rate_limit, only: [ :login ]

      def signup
        user = User.new(user_params)

        if user.save
          tokens = ApiToken.generate_token_pair(user)
          set_auth_cookies(tokens)
          render json: {
            access_token: tokens[:access_token].raw_token,
            refresh_token: tokens[:refresh_token].raw_token,
            user: user_response(user)
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def login
        user = User.find_by(email: params[:email])

        if user&.authenticate(params[:password])
          # 古いトークンをクリーンアップ
          ApiToken.cleanup_old_tokens(user.id)

          tokens = ApiToken.generate_token_pair(user)
          set_auth_cookies(tokens)
          render json: {
            access_token: tokens[:access_token].raw_token,
            refresh_token: tokens[:refresh_token].raw_token,
            user: user_response(user)
          }, status: :ok
        else
          render json: { error: "メールアドレスまたはパスワードが不正です" }, status: :unauthorized
        end
      end

      def refresh
        refresh_token_value = params[:refresh_token]

        if refresh_token_value.blank?
          return render json: { error: "リフレッシュトークンが必要です" }, status: :unauthorized
        end

        # リフレッシュトークンを検索
        token_record = ApiToken.find_by_refresh_token(refresh_token_value)

        # トークンが存在しない場合
        if token_record.nil?
          return render json: { error: "無効または期限切れのリフレッシュトークンです" }, status: :unauthorized
        end

        # 既に無効化されているトークンの再利用を検知
        if token_record.revoked_at.present?
          # セキュリティ：トークンチェーン全体を無効化
          if token_record.token_family_id.present?
            ApiToken.where(token_family_id: token_record.token_family_id)
                    .update_all(revoked_at: Time.current)
          end
          return render json: { error: "トークンの再利用が検出されました" }, status: :unauthorized
        end

        # トークンの有効期限チェック
        if !token_record.refresh_valid?
          return render json: { error: "無効または期限切れのリフレッシュトークンです" }, status: :unauthorized
        end

        user = token_record.user

        # 同じレコードでトークンをローテーション
        new_tokens = token_record.rotate_tokens!

        render json: {
          access_token: new_tokens[:access_token].raw_token,
          refresh_token: new_tokens[:refresh_token].raw_token
        }, status: :ok
      end

      def logout
        # アクセストークンを取得
        token_value = extract_token_from_header

        if token_value.blank?
          return render json: { error: "認証ヘッダーが必要です" }, status: :unauthorized
        end

        access_token = ApiToken.find_by_token(token_value)

        if access_token.nil?
          return render json: { error: "無効または期限切れのトークンです" }, status: :unauthorized
        end

        # アクセストークンを無効化
        access_token.update!(revoked_at: Time.current)

        # 同じユーザーの全てのアクティブトークンを無効化
        if access_token.user_id.present?
          ApiToken.where(
            user_id: access_token.user_id,
            revoked_at: nil
          ).update_all(revoked_at: Time.current)
        end

        # クッキーをクリア
        clear_auth_cookies

        render json: { message: "正常にログアウトしました" }, status: :ok
      end

      def me
        if current_user
          render json: user_response(current_user), status: :ok
        else
          render json: { error: "認証されていません" }, status: :unauthorized
        end
      end

      private

      def user_params
        params.permit(:email, :password, :name)
      end

      def user_response(user)
        {
          id: user.id,
          email: user.email,
          name: user.name
        }
      end

      def set_auth_cookies(tokens)
        # HTTP-onlyクッキーとしてトークンを設定
        cookies[:access_token] = {
          value: tokens[:access_token].raw_token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax,
          expires: 2.hours.from_now
        }

        cookies[:refresh_token] = {
          value: tokens[:refresh_token].raw_token,
          httponly: true,
          secure: Rails.env.production?,
          same_site: :lax,
          expires: 30.days.from_now
        }
      end

      def clear_auth_cookies
        cookies.delete(:access_token)
        cookies.delete(:refresh_token)
      end

      # authenticate_user!とextract_token_from_headerはApplicationControllerに移動済み

      def check_rate_limit
        # レート制限チェック（メールが提供されている場合のみ）
        return unless params[:email].present?

        # IPアドレスベースまたはメールベースのレート制限を実装
        # ここではシンプルにメールベースで実装
        cache_key = "login_attempts:#{params[:email]}"

        # Railsキャッシュを使用してカウント（実際の実装では Redis等を使用）
        attempts = Rails.cache.read(cache_key) || 0

        if attempts >= 10
          render json: { error: "リクエストが多すぎます。しばらくしてからお試しください。" }, status: :too_many_requests
          false
        else
          Rails.cache.write(cache_key, attempts + 1, expires_in: 1.minute)
        end
      end
    end
  end
end
