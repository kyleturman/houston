# frozen_string_literal: true

class Api::NotesController < Api::BaseController
  before_action :set_goal_from_nested, only: %i[index create]
  before_action :set_note, only: %i[show update destroy retry_processing ignore_processing]

  def index
    Rails.logger.info("[NotesController#index] Called with params: #{params.inspect}")
    Rails.logger.info("[NotesController#index] User: #{current_user.email}, Goal: #{@goal&.id}")

    scope = current_user.notes
    scope = scope.where(goal_id: @goal.id) if @goal

    # Cursor-based pagination using note ID
    if params[:before_id].present?
      before_note = scope.find_by(id: params[:before_id])
      scope = scope.where("created_at < ?", before_note.created_at) if before_note
    end

    per_page = (params[:per_page] || 20).to_i.clamp(1, 100)

    # Include hidden notes by default, but mark them so UI can render differently
    # Fetch one extra to determine if there's more
    notes = scope.order(created_at: :desc).limit(per_page + 1)

    has_more = notes.size > per_page
    notes = notes.first(per_page)

    response = NoteSerializer.new(notes).serializable_hash
    response[:meta] = {
      has_more: has_more,
      next_cursor: has_more ? notes.last&.id&.to_s : nil,
      per_page: per_page,
      count: notes.size
    }

    Rails.logger.info("[NotesController#index] Returning #{notes.size} notes")
    Rails.logger.info("[NotesController#index] Response: #{response.to_json[0..500]}")

    render json: response
  end

  def show
    render json: NoteSerializer.new(@note).serializable_hash
  end

  def create
    note = current_user.notes.new(note_params)
    note.goal = @goal if @goal

    # Detect URL in content (first URL only)
    url = detect_url(note.content) if note.content.present?

    if url
      # Two-phase URL processing: quick metadata fetch (sync), then full summarization (async)
      begin
        # Phase 1: Quick metadata fetch (1-2 seconds)
        # Use timeout and minimal options for speed
        fetched_data = Timeout.timeout(3) do
          Web::Service.fetch(url, clean: false, metadata: true, images: true)
        end

        # Extract user commentary (replace URL with newline, clean up multiple newlines)
        commentary = note.content.gsub(url, "\n").gsub(/\n+/, "\n").strip
        note.content = commentary.presence # nil if empty after removing URL

        # Clean and set title from SEO
        cleaned_title = clean_title(fetched_data[:title])
        note.title ||= cleaned_title

        # Extract OG image separately (for card previews)
        og_image = extract_og_image(fetched_data)

        # Extract content images (filtered, no logos/icons)
        content_images = extract_content_images(fetched_data)

        # Store metadata with processing state
        note.metadata = {
          source_url: url,
          processing_state: 'pending',
          seo: fetched_data[:metadata][:seo],
          og_image: og_image,
          images: content_images,
          og: fetched_data[:metadata][:og],
          twitter: fetched_data[:metadata][:twitter],
          assets: fetched_data[:metadata][:assets]
        }

        # Auto-assign goal using SEO title + description (fast, accurate enough)
        if note.goal_id.nil?
          seo_content = "#{fetched_data[:title]} #{fetched_data[:metadata][:seo][:description]}"
          note.goal_id = suggest_goal_for_content(seo_content)
        end

        # Save note with metadata
        if note.save
          # Queue Phase 2: Full content fetch + summarization (async)
          ProcessUrlNoteJob.perform_later(note.id)

          # Broadcast note_created event to global stream
          publish_lifecycle_event('note_created', note)

          # Queue check-in adjustment if note is assigned to a goal
          queue_check_in_adjustment(note)

          render json: NoteSerializer.new(note).serializable_hash, status: :created
        else
          render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Timeout::Error => e
        Rails.logger.warn("[NotesController] Metadata fetch timeout for URL: #{url}")
        # Fallback: Save note without metadata, queue async processing
        commentary = note.content.gsub(url, "\n").gsub(/\n+/, "\n").strip
        note.content = commentary.presence
        note.metadata = { source_url: url, processing_state: 'pending' }

        if note.save
          ProcessUrlNoteJob.perform_later(note.id)
          publish_lifecycle_event('note_created', note)
          queue_check_in_adjustment(note)
          render json: NoteSerializer.new(note).serializable_hash, status: :created
        else
          render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error("[NotesController] Failed to fetch metadata for URL: #{e.message}")
        # Fallback: Save note without metadata, queue async processing
        commentary = note.content.gsub(url, "\n").gsub(/\n+/, "\n").strip
        note.content = commentary.presence
        note.metadata = { source_url: url, processing_state: 'pending' }

        if note.save
          ProcessUrlNoteJob.perform_later(note.id)
          publish_lifecycle_event('note_created', note)
          queue_check_in_adjustment(note)
          render json: NoteSerializer.new(note).serializable_hash, status: :created
        else
          render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
        end
      end
    else
      # No URL detected: keep existing flow
      # Auto-assign goal using LLM if no goal is assigned
      if note.goal_id.nil? && note.content.present?
        note.goal_id = suggest_goal_for_content(note.content)
      end

      if note.save
        # Broadcast note_created event to global stream
        publish_lifecycle_event('note_created', note)

        # Queue check-in adjustment if note is assigned to a goal
        queue_check_in_adjustment(note)

        render json: NoteSerializer.new(note).serializable_hash, status: :created
      else
        render json: { errors: note.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  def update
    # Prevent moving the note to a goal not owned by the user
    if note_params[:goal_id].present?
      new_goal = current_user.goals.find_by(id: note_params[:goal_id])
      return render json: { error: 'Goal not found' }, status: :not_found if new_goal.nil?
    end

    if @note.update(note_params)
      # Broadcast note_updated event to global stream
      publish_lifecycle_event('note_updated', @note)

      render json: NoteSerializer.new(@note).serializable_hash
    else
      render json: { errors: @note.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    note_id = @note.id
    goal_id = @note.goal_id

    @note.destroy

    # Broadcast note_deleted event to global stream
    publish_lifecycle_event('note_deleted', nil, { note_id: note_id, goal_id: goal_id })

    head :no_content
  end

  def retry_processing
    unless @note.metadata['processing_state'] == 'failed'
      return render json: { error: 'Note processing has not failed' }, status: :unprocessable_entity
    end

    unless @note.metadata['source_url'].present?
      return render json: { error: 'Note does not have a source URL' }, status: :unprocessable_entity
    end

    # Reset processing state to pending
    @note.metadata = @note.metadata.merge('processing_state' => 'pending')
    @note.save!

    # Re-queue the background job
    ProcessUrlNoteJob.perform_later(@note.id)

    # Broadcast update event
    publish_lifecycle_event('note_updated', @note)

    render json: { success: true, message: 'Processing restarted' }
  rescue => e
    Rails.logger.error("[NotesController] Failed to retry processing: #{e.message}")
    render json: { error: 'Failed to retry processing' }, status: :internal_server_error
  end

  def ignore_processing
    unless @note.metadata['processing_state'] == 'failed'
      return render json: { error: 'Note processing has not failed' }, status: :unprocessable_entity
    end

    # Set processing state to ignored (no more retry prompts)
    @note.metadata = @note.metadata.merge('processing_state' => 'ignored')
    @note.save!

    # Broadcast update event
    publish_lifecycle_event('note_updated', @note)

    render json: { success: true, message: 'Processing failure ignored' }
  rescue => e
    Rails.logger.error("[NotesController] Failed to ignore processing: #{e.message}")
    render json: { error: 'Failed to ignore processing' }, status: :internal_server_error
  end

  private

  def set_goal_from_nested
    return unless params[:goal_id].present?
    @goal = current_user.goals.find(params[:goal_id])
  end

  def set_note
    @note = current_user.notes.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:title, :content, :source, :goal_id, { metadata: {} })
  end

  def detect_url(text)
    # Simple URL detection using Ruby's URI module
    uri = URI.extract(text, ['http', 'https']).first
    uri
  end

  # Clean title by removing common suffixes
  def clean_title(title)
    return title if title.blank?

    # Remove common video/media suffixes
    cleaned = title.gsub(/\s*\((with\s+)?video\)/i, '')
                   .gsub(/\s*\[video\]/i, '')
                   .gsub(/\s*-\s*video$/i, '')

    cleaned.strip
  end

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
    images = fetched_data[:images] || []
    return [] if images.empty?

    images.map { |img| { url: img[:url], alt: img[:alt] } }
  end

  def suggest_goal_for_content(content)
    # Include both working and waiting goals (exclude only archived)
    goals = current_user.goals.active.order(created_at: :desc)
    return nil if goals.empty?

    system_prompt = <<~PROMPT
      You are helping a user organize their notes by suggesting which goal (if any) a note should be associated with.

      The user has the following active goals:
      #{goals.map { |g| "- ID: #{g.id}, Title: #{g.title}, Description: #{g.description}" }.join("\n")}

      Based on the note content provided, determine if it relates to any of these goals.
      Respond with ONLY the goal ID number if it clearly relates to a specific goal, or "none" if it doesn't relate to any goal.
      Be conservative - only suggest a goal if there's a clear connection.
    PROMPT

    result = Llms::Service.call(
      system: system_prompt,
      messages: [{ role: "user", content: "Note content: #{content}" }],
      user: current_user
    )

    # Extract text from content array
    text = result[:content]
      .select { |block| block[:type] == :text }
      .map { |block| block[:text] }
      .join("\n")
    suggested_id = text.strip
    suggested_id&.match?(/^\d+$/) ? suggested_id.to_i : nil
  rescue => e
    Rails.logger.error("Error suggesting goal: #{e.message}")
    nil
  end

  # Publish lifecycle event to global stream
  # @param event_name [String] The event name (e.g., 'note_created')
  # @param note [Note, nil] The note object (nil for delete events)
  # @param extra_data [Hash] Additional data to include in the event
  def publish_lifecycle_event(event_name, note, extra_data = {})
    channel = Streams::Channels.global_for_user(user: current_user)

    data = if note
      {
        note_id: note.id,
        goal_id: note.goal_id,
        title: note.title,
        created_at: note.created_at&.iso8601,
        updated_at: note.updated_at&.iso8601
      }.merge(extra_data)
    else
      extra_data
    end

    Streams::Broker.publish(
      channel,
      event: event_name,
      data: data
    )

    # Also broadcast goal_updated so iOS refreshes counts
    goal_id = note&.goal_id || extra_data[:goal_id]
    if goal_id
      goal = Goal.find_by(id: goal_id)
      if goal
        Streams::Broker.publish(
          channel,
          event: 'goal_updated',
          data: {
            goal_id: goal.id,
            title: goal.title,
            status: goal.status
          }
        )
      end
    end

    Rails.logger.info("[NotesController] Published #{event_name} to global stream for user #{current_user.id}")
  rescue => e
    # Don't fail the request if SSE publishing fails
    Rails.logger.error("[NotesController] Failed to publish #{event_name}: #{e.message}")
  end

  # Queue check-in adjustment when a note is created
  # This ensures the agent reviews new notes within a reasonable time
  # @param note [Note] The created note
  def queue_check_in_adjustment(note)
    return unless note.goal_id.present?

    # Small delay to batch rapid notes and let the request complete first
    NoteTriggeredCheckInJob.perform_in(5.seconds, note.goal_id)
  rescue => e
    # Don't fail the request if job queueing fails
    Rails.logger.error("[NotesController] Failed to queue check-in adjustment: #{e.message}")
  end
end
