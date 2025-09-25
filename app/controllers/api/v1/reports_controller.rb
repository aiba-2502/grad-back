module Api
  module V1
    class ReportsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_report_service

      # レポートデータ取得（分析必要性チェック付き）
      def show
        report_data = @report_service.generate_report
        render json: report_data
      end

      # 手動分析実行
      def analyze
        # レート制限チェック（1分に1回まで）
        if rate_limited?
          render json: {
            error: "分析は1分に1回まで実行可能です。しばらくお待ちください。",
            retry_after: rate_limit_retry_after
          }, status: :too_many_requests
          return
        end

        # レート制限カウンターを記録
        record_rate_limit

        analysis_result = @report_service.execute_analysis
        render json: analysis_result
      rescue => e
        Rails.logger.error "Analysis failed for user #{current_user.id}: #{e.message}"
        render json: { error: "分析に失敗しました。しばらくしてから再試行してください。" }, status: :internal_server_error
      end

      def weekly
        weekly_report = @report_service.generate_weekly_report
        render json: weekly_report
      end

      def monthly
        monthly_report = @report_service.generate_monthly_report
        render json: monthly_report
      end

      private

      def set_report_service
        @report_service = ReportService.new(current_user)
      end

      # レート制限チェック
      def rate_limited?
        cache_key = "report_analysis_rate_limit:#{current_user.id}"
        Rails.cache.exist?(cache_key)
      end

      # レート制限カウンターを記録
      def record_rate_limit
        cache_key = "report_analysis_rate_limit:#{current_user.id}"
        Rails.cache.write(cache_key, true, expires_in: 1.minute)
      end

      # 次回実行可能までの秒数
      def rate_limit_retry_after
        # MemoryStoreを使用しているため、固定値60秒を返す
        60
      end
    end
  end
end
