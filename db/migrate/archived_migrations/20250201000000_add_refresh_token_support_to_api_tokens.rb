class AddRefreshTokenSupportToApiTokens < ActiveRecord::Migration[8.0]
  def change
    # api_tokensテーブルに最小限のカラムを追加
    add_column :api_tokens, :token_type, :string, limit: 20, default: 'access', null: false
    add_column :api_tokens, :family_id, :string
    add_column :api_tokens, :revoked_at, :datetime

    # 新規インデックスを追加
    add_index :api_tokens, :token_type
    add_index :api_tokens, :family_id
    add_index :api_tokens, :revoked_at
    add_index :api_tokens, [ :user_id, :token_type, :revoked_at ], name: 'idx_api_tokens_user_type_revoked'
    add_index :api_tokens, [ :family_id, :created_at ], name: 'idx_api_tokens_family_created'

    # 既存データの移行
    # 既存のトークンはすべてアクセストークンとして扱う
    execute "UPDATE api_tokens SET token_type = 'access' WHERE token_type IS NULL" if ApiToken.any?
  end

  def down
    # インデックスを削除
    remove_index :api_tokens, name: 'idx_api_tokens_family_created'
    remove_index :api_tokens, name: 'idx_api_tokens_user_type_revoked'
    remove_index :api_tokens, :revoked_at
    remove_index :api_tokens, :family_id
    remove_index :api_tokens, :token_type

    # カラムを削除
    remove_column :api_tokens, :revoked_at
    remove_column :api_tokens, :family_id
    remove_column :api_tokens, :token_type
  end
end
