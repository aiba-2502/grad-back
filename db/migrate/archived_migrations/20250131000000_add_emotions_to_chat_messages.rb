class AddEmotionsToChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :chat_messages, :emotions, :jsonb, default: []
    add_index :chat_messages, :emotions, using: :gin
  end
end
