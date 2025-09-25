module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_user!

      def me
        render json: user_response(@current_user), status: :ok
      end

      def update
        # ユーザー情報を更新（名前とメールのみ）
        if @current_user.update(user_update_params)
          render json: {
            user: user_response(@current_user),
            message: "プロフィールを更新しました"
          }, status: :ok
        else
          render json: {
            error: "更新に失敗しました",
            errors: @current_user.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def user_update_params
        params.permit(:name, :email)
      end

      def user_response(user)
        {
          id: user.id,
          email: user.email,
          name: user.name,
          created_at: user.created_at,
          updated_at: user.updated_at
        }
      end
    end
  end
end
