require "net/http"
require "json"
require "base64"

module Api
  module V1
    class VoicesController < ApplicationController
      # 音声生成は認証不要（フロントエンドから直接呼び出し）
      # 必要に応じてbefore_actionで認証を追加可能

      def generate
        text = params[:text]

        if text.blank?
          render json: { error: "読み上げるテキストが指定されていません" }, status: :bad_request
          return
        end

        begin
          voice_data = generate_voice(text)
          render json: voice_data
        rescue => e
          Rails.logger.error "Voice generation failed: #{e.message}"
          render json: { error: "音声生成に失敗しました" }, status: :internal_server_error
        end
      end

      private

      def generate_voice(text)
        api_key = ENV["NIJIVOICE_API_KEY"]
        voice_id = ENV["NIJIVOICE_VOICE_ID"]

        if api_key.blank? || voice_id.blank?
          raise "にじボイスAPIの設定が不完全です"
        end

        # generate-encoded-voiceエンドポイントを使用してBase64データを直接取得
        uri = URI("https://api.nijivoice.com/api/platform/v1/voice-actors/#{voice_id}/generate-encoded-voice")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["x-api-key"] = api_key

        # にじボイスAPIの仕様に合わせたパラメータ
        speed = ENV["NIJIVOICE_SPEED"] || "1.0"
        request_body = {
          script: text,  # scriptフィールドが必須
          speed: speed,  # 文字列として送信
          format: "wav"
        }

        request.body = request_body.to_json

        response = http.request(request)

        case response.code.to_i
        when 200
          data = JSON.parse(response.body)
          Rails.logger.info "NijiVoice API Response keys: #{data.keys.inspect}"

          # generate-encoded-voiceのレスポンスからBase64音声データを取得
          base64_audio = data.dig("generatedVoice", "base64Audio")

          if base64_audio
            # Base64データを返す
            { audioData: base64_audio }
          else
            # フォールバック: 旧形式のレスポンスもサポート
            audio_url = data.dig("generatedVoice", "audioFileUrl") ||
                       data.dig("generatedVoice", "audioFileDownloadUrl")

            if audio_url
              # 外部URLから音声データを取得してBase64に変換
              begin
                audio_response = Net::HTTP.get_response(URI(audio_url))
                if audio_response.code.to_i == 200
                  base64_data = Base64.strict_encode64(audio_response.body)
                  { audioData: base64_data }
                else
                  Rails.logger.error "Failed to fetch audio from URL: #{audio_url}, Status: #{audio_response.code}"
                  raise "音声データの取得に失敗しました"
                end
              rescue => e
                Rails.logger.error "Error fetching audio from URL: #{e.message}"
                raise "音声データの取得に失敗しました"
              end
            else
              raise "音声データが取得できませんでした"
            end
          end
        when 401
          raise "APIキーが無効です"
        when 404
          raise "ボイスIDが見つかりません"
        when 429
          raise "API利用制限に達しました"
        when 400
          raise "リクエストパラメータが不正です"
        else
          raise "APIエラー: #{response.code}"
        end
      end
    end
  end
end
