# frozen_string_literal: true

# Manual test script for URL note processing
# Usage: docker-compose exec backend rails runner scripts/test_url_note.rb

puts "========================================="
puts "URL Note Processing Test Script"
puts "=========================================\n\n"

# Find or create test user
user = User.first || User.create!(email: 'test@example.com')
puts "Using user: #{user.email} (ID: #{user.id})"

# Create a test goal
goal = Goal.create!(
  user: user,
  title: 'Web Development Learning',
  description: 'Learn about web development technologies',
  status: :working
)
puts "Created goal: #{goal.title} (ID: #{goal.id})\n\n"

# Single test case - use a URL that's likely to work
test_content = "Check this out:\nhttps://github.com/trending\nReally cool repos!"
puts "-------------------------------------------"
puts "Testing URL Note Processing"
puts "-------------------------------------------"
puts "Input: #{test_content.inspect}\n\n"

# Simulate controller logic - detect URL and process
url = URI.extract(test_content, ['http', 'https']).first

if url
  puts "URL detected: #{url}"

  # Simulate quick metadata fetch
  begin
    fetched_data = Timeout.timeout(3) do
      Web::Service.fetch(url, clean: false, metadata: true, images: true)
    end

    # Extract commentary - replace URL with newline
    commentary = test_content.gsub(url, "\n").gsub(/\n+/, "\n").strip
    content = commentary.presence

    # Create note with metadata
    note = Note.create!(
      user: user,
      goal: goal,
      title: fetched_data[:title],
      content: content,
      source: :user,
      metadata: {
        'source_url' => url,
        'processing_state' => 'pending',
        'seo' => fetched_data[:metadata][:seo]
      }
    )

    puts "✓ Note created (ID: #{note.id})"
    puts "  Title: #{note.title || '(none)'}"
    puts "  Content: #{note.content&.inspect || '(none)'}"
    puts "  Metadata:"
    puts "    source_url: #{note.metadata['source_url']}"
    puts "    processing_state: #{note.metadata['processing_state']}"
    puts "    seo_title: #{note.metadata['seo']&.dig('title')}"
    puts "    seo_description: #{note.metadata['seo']&.dig('description')&.truncate(80)}"
    puts "  Goal ID: #{note.goal_id}"
    puts ""

    # Queue background job and wait for it to complete
    puts "Queuing background job for async processing..."
    ProcessUrlNoteJob.perform_later(note.id)

    puts "Waiting for background job to complete (polling every 2s, max 30s)..."
    max_wait = 30
    elapsed = 0

    while elapsed < max_wait
      sleep 2
      elapsed += 2
      note.reload

      state = note.metadata['processing_state']
      puts "  [#{elapsed}s] processing_state: #{state}"

      if state == 'completed'
        puts "\n✅ Processing completed successfully!"
        break
      elsif state == 'failed'
        puts "\n❌ Processing failed"
        break
      end
    end

    if elapsed >= max_wait
      puts "\n⏱️  Timeout reached (#{max_wait}s) - processing still pending"
    end

    # Show final state
    note.reload
    puts "\n-------------------------------------------"
    puts "Final Note State"
    puts "-------------------------------------------"
    puts "  processing_state: #{note.metadata['processing_state']}"
    puts "  web_summary: #{note.metadata['web_summary']&.truncate(200) || '(none)'}"
    puts "  images: #{note.metadata['images']&.length || 0} images"

    if note.metadata['images']&.any?
      puts "\n  Image URLs:"
      note.metadata['images'].each_with_index do |img, i|
        puts "    #{i + 1}. #{img['url']}"
      end
    end

  rescue => e
    puts "❌ Error during processing: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
else
  puts "❌ No URL detected in content"
end

puts "\n==========================================="
puts "To inspect the note in Rails console:"
puts "  docker-compose exec backend rails console"
puts "  Note.find(#{note&.id})"
puts ""
puts "To clean up:"
puts "  Goal.find(#{goal.id}).destroy"
puts "==========================================="
