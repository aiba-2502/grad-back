namespace :migration do
  desc "Final cleanup - Remove chat_messages table (WARNING: This is irreversible!)"
  task cleanup_chat_messages: :environment do
    puts "\n" + "="*70
    puts " WARNING: THIS WILL PERMANENTLY DELETE THE CHAT_MESSAGES TABLE!"
    puts "="*70
    puts "\nThis task will:"
    puts "  1. Stop writing to chat_messages table"
    puts "  2. Remove ChatMessage model references"
    puts "  3. Drop the chat_messages table"
    puts "\nMake sure you have:"
    puts "  ✓ Successfully migrated all data to chats/messages tables"
    puts "  ✓ Verified the migration is complete"
    puts "  ✓ Tested the application works without chat_messages"
    puts "  ✓ Created a database backup"
    puts "\nType 'DELETE_CHAT_MESSAGES' to proceed:"

    input = STDIN.gets.chomp

    unless input == "DELETE_CHAT_MESSAGES"
      puts "Cleanup cancelled."
      exit
    end

    puts "\nStarting cleanup process..."

    # Step 1: Verify migration completeness
    chat_message_count = ChatMessage.count
    message_count = Message.count

    if chat_message_count != message_count
      puts "⚠️  WARNING: Message counts don't match!"
      puts "   ChatMessages: #{chat_message_count}"
      puts "   Messages: #{message_count}"
      puts "\nDo you still want to proceed? Type 'yes' to continue:"

      confirm = STDIN.gets.chomp
      unless confirm.downcase == "yes"
        puts "Cleanup cancelled."
        exit
      end
    end

    # Step 2: Create final backup
    backup_file = Rails.root.join("tmp", "chat_messages_final_backup_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")
    puts "\nCreating final backup to: #{backup_file}"

    File.open(backup_file, "w") do |file|
      ChatMessage.find_in_batches(batch_size: 1000) do |batch|
        batch.each do |cm|
          file.write(cm.to_json)
          file.write("\n")
        end
      end
    end

    puts "Backup created: #{backup_file}"

    # Step 3: Drop the table
    puts "\nDropping chat_messages table..."
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS chat_messages CASCADE")

    puts "\n" + "="*50
    puts "Cleanup completed successfully!"
    puts "="*50
    puts "\nNext steps:"
    puts "  1. Remove ChatMessage model file"
    puts "  2. Update ChatsController to remove parallel writes"
    puts "  3. Deploy changes"
    puts "  4. Monitor for any issues"
  end

  desc "Generate cleanup checklist"
  task cleanup_checklist: :environment do
    puts "\n" + "="*50
    puts " CHAT_MESSAGES CLEANUP CHECKLIST"
    puts "="*50

    checks = []

    # Check 1: Data migration
    chat_message_count = ChatMessage.count
    message_count = Message.count
    checks << {
      name: "Data Migration Complete",
      status: chat_message_count == message_count,
      details: "ChatMessages: #{chat_message_count}, Messages: #{message_count}"
    }

    # Check 2: Recent activity
    recent_chat_messages = ChatMessage.where("created_at > ?", 1.hour.ago).count
    recent_messages = Message.where("sent_at > ?", 1.hour.ago).count
    checks << {
      name: "Recent Messages Syncing",
      status: recent_chat_messages == recent_messages,
      details: "Recent ChatMessages: #{recent_chat_messages}, Recent Messages: #{recent_messages}"
    }

    # Check 3: Frontend compatibility
    checks << {
      name: "Frontend Adapter Deployed",
      status: File.exist?(Rails.root.join("..", "frontend", "src", "utils", "chatAdapter.ts")),
      details: "chatAdapter.ts exists"
    }

    # Check 4: Backup exists
    backup_exists = Dir.glob(Rails.root.join("tmp", "chat_messages_final_backup_*.json")).any?
    checks << {
      name: "Backup Created",
      status: backup_exists,
      details: backup_exists ? "Backup file exists" : "No backup found"
    }

    # Display results
    all_passed = true
    checks.each do |check|
      status_icon = check[:status] ? "✅" : "❌"
      puts "\n#{status_icon} #{check[:name]}"
      puts "   #{check[:details]}"
      all_passed = false unless check[:status]
    end

    puts "\n" + "="*50
    if all_passed
      puts "✅ All checks passed! Ready for cleanup."
    else
      puts "❌ Some checks failed. Please resolve issues before cleanup."
    end
    puts "="*50
  end
end
