namespace :migration do
  desc "Migrate chat_messages to chats and messages tables"
  task migrate_chat_messages: :environment do
    puts "Starting migration from chat_messages to chats and messages tables..."

    start_time = Time.current
    total_messages = ChatMessage.count
    migrated_count = 0
    error_count = 0
    batch_size = 1000

    puts "Total messages to migrate: #{total_messages}"

    # Process messages in batches
    ChatMessage.find_in_batches(batch_size: batch_size) do |batch|
      ActiveRecord::Base.transaction do
        batch.each do |cm|
          begin
            # 1. Find or create Chat record
            chat_session_service = ChatSessionService.new
            chat = chat_session_service.find_or_create_chat(cm.session_id, cm.user)

            # 2. Check if message already exists (prevent duplicates)
            existing_message = Message.find_by(
              chat: chat,
              sender: cm.user,
              sent_at: cm.created_at
            )

            if existing_message
              puts "Message already migrated: ChatMessage ##{cm.id}"
              migrated_count += 1
              next
            end

            # 3. Sync to Messages table
            message_sync_service = MessageSyncService.new
            message = message_sync_service.sync_to_messages_table(cm, chat)

            if message.persisted?
              migrated_count += 1
              print "." if migrated_count % 100 == 0
            else
              error_count += 1
              puts "\nFailed to migrate ChatMessage ##{cm.id}: #{message.errors.full_messages.join(', ')}"
            end
          rescue => e
            error_count += 1
            puts "\nError migrating ChatMessage ##{cm.id}: #{e.message}"
          end
        end
      end

      # Progress update
      puts "\nProgress: #{migrated_count}/#{total_messages} migrated (#{error_count} errors)"
    end

    # Final statistics
    end_time = Time.current
    duration = (end_time - start_time).round(2)

    puts "\n" + "="*50
    puts "Migration completed!"
    puts "Total messages: #{total_messages}"
    puts "Successfully migrated: #{migrated_count}"
    puts "Errors: #{error_count}"
    puts "Duration: #{duration} seconds"
    puts "="*50

    # Verification
    Rake::Task["migration:verify_migration"].invoke
  end

  desc "Verify migration integrity"
  task verify_migration: :environment do
    puts "\nVerifying migration integrity..."

    chat_message_count = ChatMessage.count
    message_count = Message.count

    if chat_message_count == message_count
      puts "✅ Message counts match: #{message_count}"
    else
      puts "⚠️  Message count mismatch!"
      puts "   ChatMessages: #{chat_message_count}"
      puts "   Messages: #{message_count}"
    end

    # Sample verification
    sample_size = [ 100, ChatMessage.count ].min
    mismatched = []

    ChatMessage.limit(sample_size).each do |cm|
      chat = Chat.find_by(title: "session:#{cm.session_id}", user: cm.user)

      if chat.nil?
        mismatched << "Missing chat for session: #{cm.session_id}"
        next
      end

      message = Message.find_by(
        chat: chat,
        content: cm.content,
        sent_at: cm.created_at
      )

      if message.nil?
        mismatched << "Missing message for ChatMessage ##{cm.id}"
      end
    end

    if mismatched.empty?
      puts "✅ Sample verification passed (#{sample_size} records checked)"
    else
      puts "⚠️  Sample verification found #{mismatched.length} issues:"
      mismatched.first(10).each { |issue| puts "   - #{issue}" }
    end
  end

  desc "Rollback migration (delete migrated data)"
  task rollback_migration: :environment do
    puts "Are you sure you want to rollback the migration? This will delete data from chats and messages tables."
    puts "Type 'yes' to continue:"

    input = STDIN.gets.chomp

    unless input.downcase == "yes"
      puts "Rollback cancelled."
      exit
    end

    puts "Starting rollback..."

    # Delete Messages first (due to foreign key constraint)
    deleted_messages = Message.destroy_all.count
    puts "Deleted #{deleted_messages} messages"

    # Delete Chats with session pattern
    deleted_chats = Chat.where("title LIKE ?", "session:%").destroy_all.count
    puts "Deleted #{deleted_chats} chats"

    puts "Rollback completed!"
  end
end
