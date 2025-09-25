class CreateChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.text :content
      t.string :role
      t.string :session_id
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :chat_messages, :session_id
    add_index :chat_messages, :role
  end
end
