class ConsolidateApiTokensToSingleRecord < ActiveRecord::Migration[8.0]
  def up
    # 新しいカラムを追加
    add_column :api_tokens, :encrypted_access_token, :string, limit: 191
    add_column :api_tokens, :encrypted_refresh_token, :string, limit: 191
    add_column :api_tokens, :access_expires_at, :datetime
    add_column :api_tokens, :refresh_expires_at, :datetime

    # インデックスを追加
    add_index :api_tokens, :encrypted_access_token, unique: true
    add_index :api_tokens, :encrypted_refresh_token, unique: true

    # 既存のトークンデータを移行（重複を避けるため処理順を工夫）

    # まず全てのトークンに一時的なカラムをセット（後で統合のために使用）
    execute <<-SQL
      -- リフレッシュトークンを新しいカラムに移行
      UPDATE api_tokens
      SET encrypted_refresh_token = encrypted_token,
          refresh_expires_at = expires_at
      WHERE token_kind = 'refresh';
    SQL

    # リフレッシュトークンとペアのアクセストークンを統合
    processed_access_ids = []

    ApiToken.where(token_kind: "refresh").find_each do |refresh_token|
      # 同じ token_family_idまたは近い時刻のアクセストークンを探す
      access_token = if refresh_token.token_family_id.present?
        ApiToken.where(
          user_id: refresh_token.user_id,
          token_kind: "access",
          token_family_id: refresh_token.token_family_id
        ).first
      else
        ApiToken.where(
          user_id: refresh_token.user_id,
          token_kind: "access",
          created_at: (refresh_token.created_at - 1.minute)..(refresh_token.created_at + 1.minute)
        ).first
      end

      if access_token
        # リフレッシュトークンのレコードに統合
        refresh_token.update_columns(
          encrypted_access_token: access_token.encrypted_token,
          access_expires_at: access_token.expires_at
        )
        # 処理済みのアクセストークンIDを記録
        processed_access_ids << access_token.id
      end
    end

    # 処理済みのアクセストークンを削除
    ApiToken.where(id: processed_access_ids).destroy_all if processed_access_ids.any?

    # 残った単独のアクセストークンを処理（リフレッシュトークンとペアでないもの）
    ApiToken.where(token_kind: "access").find_each do |token|
      token.update_columns(
        encrypted_access_token: token.encrypted_token,
        access_expires_at: token.expires_at
      )
    end

    # 古いカラムとインデックスを削除
    remove_index :api_tokens, :encrypted_token if index_exists?(:api_tokens, :encrypted_token)
    remove_index :api_tokens, :token_kind if index_exists?(:api_tokens, :token_kind)

    # name付きインデックスの削除
    begin
      remove_index :api_tokens, name: 'idx_api_tokens_user_kind_revoked'
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # インデックスが存在しない場合はスキップ
    end

    remove_column :api_tokens, :encrypted_token
    remove_column :api_tokens, :expires_at
    remove_column :api_tokens, :token_kind
  end

  def down
    # 元のカラムを復元
    add_column :api_tokens, :encrypted_token, :string, limit: 191
    add_column :api_tokens, :expires_at, :datetime
    add_column :api_tokens, :token_kind, :string, limit: 20, default: "access", null: false

    # インデックスを復元
    add_index :api_tokens, :encrypted_token, unique: true
    add_index :api_tokens, :token_kind
    add_index :api_tokens, [ :user_id, :token_kind, :revoked_at ], name: 'idx_api_tokens_user_kind_revoked'

    # データを元に戻す（統合されたレコードを分割）
    ApiToken.find_each do |token|
      if token.encrypted_access_token.present? && token.encrypted_refresh_token.present?
        # 両方のトークンがある場合、2つのレコードに分割
        # リフレッシュトークンとして現在のレコードを更新
        token.update_columns(
          encrypted_token: token.encrypted_refresh_token,
          expires_at: token.refresh_expires_at,
          token_kind: "refresh"
        )

        # アクセストークンとして新しいレコードを作成
        ApiToken.create!(
          user_id: token.user_id,
          encrypted_token: token.encrypted_access_token,
          expires_at: token.access_expires_at,
          token_kind: "access",
          token_family_id: token.token_family_id,
          revoked_at: token.revoked_at,
          created_at: token.created_at,
          updated_at: token.updated_at
        )
      elsif token.encrypted_access_token.present?
        # アクセストークンのみの場合
        token.update_columns(
          encrypted_token: token.encrypted_access_token,
          expires_at: token.access_expires_at,
          token_kind: "access"
        )
      elsif token.encrypted_refresh_token.present?
        # リフレッシュトークンのみの場合
        token.update_columns(
          encrypted_token: token.encrypted_refresh_token,
          expires_at: token.refresh_expires_at,
          token_kind: "refresh"
        )
      end
    end

    # 新しいカラムとインデックスを削除
    remove_index :api_tokens, :encrypted_access_token if index_exists?(:api_tokens, :encrypted_access_token)
    remove_index :api_tokens, :encrypted_refresh_token if index_exists?(:api_tokens, :encrypted_refresh_token)

    remove_column :api_tokens, :encrypted_access_token
    remove_column :api_tokens, :encrypted_refresh_token
    remove_column :api_tokens, :access_expires_at
    remove_column :api_tokens, :refresh_expires_at
  end
end
