class AddSenderKindToMessages < ActiveRecord::Migration[8.0]
  def up
    # sender_kindカラムを追加（NOT NULL制約付き、デフォルト値なし）
    add_column :messages, :sender_kind, :string

    # 既存データの更新
    # llm_metadataの'role'フィールドを参照してsender_kindを設定
    execute <<-SQL
      UPDATE messages
      SET sender_kind = CASE
        WHEN llm_metadata->>'role' = 'assistant' THEN 'ASSISTANT'
        ELSE 'USER'
      END
    SQL

    # NOT NULL制約を追加
    change_column_null :messages, :sender_kind, false

    # インデックスを追加（クエリのパフォーマンス向上）
    add_index :messages, :sender_kind
  end

  def down
    remove_index :messages, :sender_kind
    remove_column :messages, :sender_kind
  end
end
