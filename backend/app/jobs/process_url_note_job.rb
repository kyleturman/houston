# frozen_string_literal: true

# Background job to process URL notes asynchronously
# Fetches full web content and generates AI summary
class ProcessUrlNoteJob < ApplicationJob
  queue_as :default

  def perform(note_id)
    note = Note.find_by(id: note_id)
    return unless note
    return unless note.metadata['source_url'].present?

    url = note.metadata['source_url']
    Rails.logger.info("[ProcessUrlNoteJob] Processing note #{note_id} for URL: #{url}")

    begin
      # Fetch full web content with all options
      fetched_data = Web::Service.fetch(url, clean: true, metadata: true, images: true)

      # Summarize content using LLM
      summary = Llms::Service.summarize(
        content: fetched_data[:content],
        url: url,
        title: fetched_data[:title],
        description: fetched_data[:metadata][:seo][:description],
        user: note.user,
        length: :concise
      )

      # Extract OG image separately (for card previews)
      og_image = extract_og_image(fetched_data)

      # Extract content images (filtered, no logos/icons)
      content_images = extract_content_images(fetched_data)

      # Update note with enriched metadata
      note.metadata = note.metadata.merge(
        'web_summary' => summary,
        'processing_state' => 'completed',
        'fetched_at' => fetched_data[:fetched_at],
        'og_image' => og_image,
        'images' => content_images,
        'og' => fetched_data[:metadata][:og],
        'twitter' => fetched_data[:metadata][:twitter],
        'assets' => fetched_data[:metadata][:assets]
      )

      note.save!

      Rails.logger.info("[ProcessUrlNoteJob] Successfully processed note #{note_id}")

      # Broadcast note_updated event to global stream
      publish_lifecycle_event('note_updated', note)
    rescue => e
      Rails.logger.error("[ProcessUrlNoteJob] Failed to process note #{note_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Mark as failed but preserve original data
      note.metadata = note.metadata.merge('processing_state' => 'failed')
      note.save!

      # Still broadcast update so UI can show error state
      publish_lifecycle_event('note_updated', note)
    end
  end

  private

  # Extract OG image for card preview (separate from content images)
  def extract_og_image(fetched_data)
    # Prefer OG image, fallback to Twitter image
    og_url = fetched_data[:metadata][:og][:image] || fetched_data[:metadata][:twitter][:image]
    return nil unless og_url

    { url: og_url, alt: 'Preview image' }
  end

  # Extract content images (already filtered by Web::Service)
  # These are meaningful images from the article, not logos/icons
  def extract_content_images(fetched_data)
    return [] unless fetched_data[:metadata][:assets][:images].present?

    fetched_data[:metadata][:assets][:images].map do |img|
      { url: img[:url], alt: img[:alt] }
    end
  end

  def publish_lifecycle_event(event_name, note)
    channel = Streams::Channels.global_for_user(user: note.user)
    Streams::Broker.publish(channel, event: event_name, data: {
      id: note.id.to_s,
      type: 'note',
      goal_id: note.goal_id&.to_s,
      attributes: {
        title: note.title,
        content: note.content,
        metadata: note.metadata,
        source: note.source,
        created_at: note.created_at&.iso8601,
        updated_at: note.updated_at&.iso8601
      }
    })
  end
end
