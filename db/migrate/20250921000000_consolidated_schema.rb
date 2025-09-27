# frozen_string_literal: true

# Consolidated migration combining all previous migrations
# Created on 2024-09-21 to simplify migration structure
#
# This migration replaces the following 14 migration files:
# - 20250124150000_rdb_init_schema.rb
# - 20250125000000_create_chat_messages.rb
# - 20250130000000_rename_encrypted_password_to_password_digest.rb
# - 20250131000000_add_emotions_to_chat_messages.rb
# - 20250201000000_add_refresh_token_support_to_api_tokens.rb
# - 20250219000000_rename_api_tokens_columns.rb
# - 20250220000000_consolidate_api_tokens_to_single_record.rb
# - 20250220000001_fix_api_tokens_column_name.rb
# - 20250222000001_add_metadata_to_tags.rb
# - 20250222000002_add_is_active_to_tags.rb
# - 20250222000003_drop_chat_messages_table.rb
# - 20250222000004_add_sender_kind_to_messages.rb

class ConsolidatedSchema < ActiveRecord::Migration[8.0]
  def up
    # Create custom enum types
    create_enum "period_type", [ "session", "daily", "weekly", "monthly" ]

    # Create users table
    create_table :users do |t|
      t.string :name, limit: 50, null: false
      t.string :email, limit: 255, null: false
      t.string :password_digest, limit: 255, null: false
      t.datetime :birth_date
      t.timestamps null: false
    end
    add_index :users, :email, unique: true

    # Create api_tokens table
    create_table :api_tokens do |t|
      t.bigint :user_id, null: false
      t.timestamps null: false
      t.string :token_family_id
      t.datetime :revoked_at
      t.string :encrypted_access_token, limit: 191
      t.string :encrypted_refresh_token, limit: 191
      t.datetime :access_expires_at
      t.datetime :refresh_expires_at
    end
    add_index :api_tokens, :user_id
    add_index :api_tokens, :encrypted_access_token, unique: true
    add_index :api_tokens, :encrypted_refresh_token, unique: true
    add_index :api_tokens, :token_family_id
    add_index :api_tokens, [ :token_family_id, :created_at ], name: "idx_api_tokens_chain_created"
    add_index :api_tokens, :revoked_at

    # Create tags table
    create_table :tags do |t|
      t.string :name, limit: 50, null: false
      t.string :category, limit: 30
      t.timestamps null: false
      t.jsonb :metadata, default: {}
      t.boolean :is_active, default: true
    end
    add_index :tags, :name, unique: true
    add_index :tags, :category
    add_index :tags, [ :category, :is_active ]
    add_index :tags, :is_active
    add_index :tags, :metadata, using: :gin

    # Create chats table
    create_table :chats do |t|
      t.bigint :user_id, null: false
      t.bigint :tag_id
      t.string :title, limit: 120
      t.timestamps null: false
    end
    add_index :chats, :user_id
    add_index :chats, :tag_id

    # Create messages table
    create_table :messages do |t|
      t.bigint :chat_id, null: false
      t.bigint :sender_id, null: false
      t.text :content, null: false
      t.json :llm_metadata
      t.decimal :emotion_score, precision: 3, scale: 2
      t.json :emotion_keywords
      t.datetime :sent_at, null: false
      t.timestamps null: false
      t.string :sender_kind, null: false
    end
    add_index :messages, :chat_id
    add_index :messages, :sender_id
    add_index :messages, :sent_at
    add_index :messages, [ :chat_id, :sent_at ], name: "idx_messages_chat_sent"
    add_index :messages, :sender_kind

    # Add check constraint for emotion_score
    execute <<-SQL
      ALTER TABLE messages
      ADD CONSTRAINT chk_emotion_score
      CHECK (emotion_score >= 0::numeric AND emotion_score <= 1::numeric)
    SQL

    # Create summaries table
    create_table :summaries do |t|
      t.column :period, :period_type, null: false
      t.bigint :chat_id
      t.bigint :user_id
      t.datetime :tally_start_at, null: false
      t.datetime :tally_end_at, null: false
      t.json :analysis_data, default: {}, null: false
      t.timestamps null: false
    end
    add_index :summaries, :user_id
    add_index :summaries, :chat_id
    add_index :summaries, [ :chat_id, :period ]
    add_index :summaries, [ :user_id, :period, :tally_start_at ]

    # Add foreign keys
    add_foreign_key :api_tokens, :users
    add_foreign_key :chats, :users
    add_foreign_key :chats, :tags
    add_foreign_key :messages, :chats
    add_foreign_key :messages, :users, column: :sender_id
    add_foreign_key :summaries, :chats
    add_foreign_key :summaries, :users
  end

  def down
    # Drop tables in reverse order
    drop_table :summaries
    drop_table :messages
    drop_table :chats
    drop_table :tags
    drop_table :api_tokens
    drop_table :users

    # Drop custom enum types
    execute "DROP TYPE IF EXISTS period_type"
  end
end
