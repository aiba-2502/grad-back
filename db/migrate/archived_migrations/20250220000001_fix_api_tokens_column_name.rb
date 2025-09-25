class FixApiTokensColumnName < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # スペース付きのカラム名を修正
    if column_exists?(:api_tokens, " token_family_id")
      rename_column :api_tokens, " token_family_id", "token_family_id"
    end

    # スペース付きのインデックスを削除して再作成
    begin
      remove_index :api_tokens, name: "index_api_tokens_on_ token_family_id"
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # インデックスが存在しない場合はスキップ
    end

    begin
      remove_index :api_tokens, name: "idx_api_tokens_chain_created"
    rescue ArgumentError, ActiveRecord::StatementInvalid
      # インデックスが存在しない場合はスキップ
    end

    # 新しいインデックスを追加（カラム名が修正された後）
    unless index_exists?(:api_tokens, :token_family_id)
      add_index :api_tokens, :token_family_id
    end

    unless index_exists?(:api_tokens, [ :token_family_id, :created_at ], name: "idx_api_tokens_chain_created")
      add_index :api_tokens, [ :token_family_id, :created_at ], name: "idx_api_tokens_chain_created"
    end
  end

  def down
    # 元に戻す場合（実際には使わないはずですが、念のため）
    if column_exists?(:api_tokens, "token_family_id")
      rename_column :api_tokens, "token_family_id", " token_family_id"
    end

    begin
      remove_index :api_tokens, :token_family_id
    rescue ArgumentError, ActiveRecord::StatementInvalid
    end

    begin
      remove_index :api_tokens, name: "idx_api_tokens_chain_created"
    rescue ArgumentError, ActiveRecord::StatementInvalid
    end

    add_index :api_tokens, " token_family_id", name: "index_api_tokens_on_ token_family_id"
    add_index :api_tokens, [ " token_family_id", :created_at ], name: "idx_api_tokens_chain_created"
  end
end
