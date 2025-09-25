class RenameApiTokensColumns < ActiveRecord::Migration[8.0]
  def up
    # カラムが既に変更されていないかチェック
    if column_exists?(:api_tokens, :family_id)
      rename_column :api_tokens, :family_id, :token_family_id
    end

    if column_exists?(:api_tokens, :token_type)
      rename_column :api_tokens, :token_type, :token_kind
    end

    # 既存のインデックスを削除（存在する場合のみ）
    begin
      remove_index :api_tokens, name: 'idx_api_tokens_user_type_revoked'
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # インデックスが存在しない場合はスキップ
    end

    begin
      remove_index :api_tokens, name: 'idx_api_tokens_family_created'
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # インデックスが存在しない場合はスキップ
    end

    # カラム名でのインデックスを削除（rename後なので token_family_idで削除）
    if index_exists?(:api_tokens, :token_family_id)
      remove_index :api_tokens, :token_family_id
    end

    if index_exists?(:api_tokens, :token_kind)
      remove_index :api_tokens, :token_kind
    end

    # 新しいインデックスを追加
    add_index :api_tokens, :token_kind
    add_index :api_tokens, :token_family_id
    add_index :api_tokens, [ :user_id, :token_kind, :revoked_at ], name: 'idx_api_tokens_user_kind_revoked'
    add_index :api_tokens, [ :token_family_id, :created_at ], name: 'idx_api_tokens_chain_created'
  end

  def down
    # インデックスを削除
    begin
      remove_index :api_tokens, name: 'idx_api_tokens_chain_created'
    rescue ArgumentError, ActiveRecord::StatementInvalid
    end

    begin
      remove_index :api_tokens, name: 'idx_api_tokens_user_kind_revoked'
    rescue ArgumentError, ActiveRecord::StatementInvalid
    end

    remove_index :api_tokens, :token_family_id if index_exists?(:api_tokens, :token_family_id)
    remove_index :api_tokens, :token_kind if index_exists?(:api_tokens, :token_kind)

    # 元のインデックスを追加
    add_index :api_tokens, :token_type
    add_index :api_tokens, :family_id
    add_index :api_tokens, [ :user_id, :token_type, :revoked_at ], name: 'idx_api_tokens_user_type_revoked'
    add_index :api_tokens, [ :family_id, :created_at ], name: 'idx_api_tokens_family_created'

    # カラム名を元に戻す
    rename_column :api_tokens, :token_family_id, :family_id if column_exists?(:api_tokens, :token_family_id)
    rename_column :api_tokens, :token_kind, :token_type if column_exists?(:api_tokens, :token_kind)
  end
end
