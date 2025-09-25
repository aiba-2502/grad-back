class DropChatMessagesTable < ActiveRecord::Migration[8.0]
  def up
    drop_table :chat_messages
  end

  def down
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_id, null: false
      t.string :content
      t.string :role, null: false
      t.json :metadata
      t.json :emotions, default: []

      t.timestamps
    end

    add_index :chat_messages, :session_id
    add_index :chat_messages, :created_at
  end
end
