# frozen_string_literal: true

# ThreadMessage represents individual messages in a conversation thread with an agent
# that the agent chooses to send to the user outside of actual LLM history. Thread messages
# can render tool cells in the client and get updates to those tool cells as well as 
# render text responses from send_message tool.
#
# == Message Flow ==
# 1. User sends message → Creates ThreadMessage with source: :user, message_type: :text
# 2. Agent responds with send_message → Creates ThreadMessage with source: :agent, message_type: :text 
# 3. Agent uses tools → Creates ThreadMessages with source: :agent, message_type: :tool
# 4. System errors → Creates ThreadMessages with source: :error, message_type: :text
#
# == Tool Messages ==
# When a tool executes, a single ThreadMessage is created and updated:
#
# 1. Tool starts → ThreadMessage created with status: "in_progress"
#    - Client renders tool cell in loading state
#    - tool_activity_id tracks the message for updates
#
# 2. Tool progresses → Same ThreadMessage updated with new metadata
#    - Client updates the tool cell (e.g., display_message changes)
#
# 3. Tool completes → Same ThreadMessage updated with status: "success"
#    - Client updates tool cell to show final results
#
# The tool_activity_id column enables efficient lookups to update the same message
# rather than creating duplicates. Tool cells handle their own state progression
# (loading → complete) based on the tool_activity.status field.
#
# Note: Some tools (like create_note) may create multiple ThreadMessages with the
# same tool_activity_id across different agentables (e.g., one in task thread, one
# in goal thread). This is intentional for cross-posting completed work.
#
class ThreadMessage < ApplicationRecord
  belongs_to :user
  belongs_to :agentable, polymorphic: true
  belongs_to :agent_history, optional: true

  enum :source, { user: 0, agent: 1, error: 2 }
  enum :message_type, { text: 0, tool: 1 }, default: :text

  # Metadata can include references: { task_id:, note_id:, alert_id: }, or any other context
  attribute :metadata, :json, default: {}

  # Encrypt sensitive user messages and tool metadata
  encrypts :content
  encrypts :metadata

  validates :source, presence: true
  validate :agentable_belongs_to_user
  validate :content_or_metadata_present

  # Marked by orchestrators when ingested/handled
  attribute :processed, :boolean, default: false

  # Auto-generate content for tool messages before validation
  before_validation :auto_generate_content

  scope :expired, -> { where("created_at < ?", 30.days.ago) }
  scope :unprocessed, -> { where(processed: false) }
  scope :for_context, -> { order(:created_at) }
  scope :for_session, ->(agent_history_id) { where(agent_history_id: agent_history_id) }
  scope :current_session, -> { where(agent_history_id: nil) }

  # Automatically stream message to clients after creation and updates
  after_create :stream_to_clients
  after_update :stream_to_clients

  # Create and stream a message in one operation
  def self.create_and_stream!(attributes)
    message = create!(attributes)
    message
  end

  # Mark multiple messages as processed atomically
  def self.mark_processed!(message_ids)
    where(id: message_ids).update_all(processed: true, updated_at: Time.current)
  end

  # Restore processed flag (for error recovery)
  def self.mark_unprocessed!(message_ids)
    where(id: message_ids).update_all(processed: false, updated_at: Time.current)
  end

  # Get unprocessed messages for an agentable object
  def self.unprocessed_for_agent(user_id:, agentable:, source: nil)
    scope = unprocessed.where(user_id: user_id, agentable: agentable)
    scope = scope.where(source: source) if source
    scope.for_context
  end

  # Check if there are unprocessed messages for an agentable (used by Orchestrator)
  def self.has_unprocessed_for?(user:, agentable:)
    unprocessed_for_agent(user_id: user.id, agentable: agentable, source: :user).exists?
  end

  # Determine the appropriate streaming channel for this message
  def stream_channel
    Streams::Channels.for_agentable(agentable: agentable)
  end

  # Check if this message should render as a special cell (not a text bubble)
  def renders_as_cell?
    tool?
  end

  # Check if message belongs to current (non-archived) session
  def in_current_session?
    agent_history_id.nil?
  end

  # Update tool_activity.data fields in this message
  # Handles the dup/merge pattern consistently
  #
  # @param data_updates [Hash] Fields to update in tool_activity.data
  # @param top_level_updates [Hash] Optional updates to top-level tool_activity fields
  # @return [Boolean] true if update succeeded
  #
  # Example:
  #   message.update_tool_activity_data({ task_status: 'completed' })
  #   message.update_tool_activity_data({ note_id: 123 }, { display_message: 'Done!' })
  def update_tool_activity_data(data_updates = {}, top_level_updates = {})
    tool_activity = metadata['tool_activity']&.dup || {}

    # Update data fields (standardized location)
    if data_updates.present?
      data = (tool_activity['data'] || {}).dup
      data.merge!(data_updates.deep_stringify_keys)
      tool_activity['data'] = data
    end

    # Update top-level fields (status, display_message, error, etc.)
    if top_level_updates.present?
      tool_activity.merge!(top_level_updates.deep_stringify_keys)
    end

    update!(
      metadata: metadata.merge('tool_activity' => tool_activity)
    )
  end

  # Update tool_activity top-level fields only (status, display_message, etc.)
  #
  # @param updates [Hash] Fields to update at tool_activity level
  # @return [Boolean] true if update succeeded
  #
  # Example:
  #   message.update_tool_activity({ status: 'success', display_message: nil })
  def update_tool_activity(updates)
    tool_activity = metadata['tool_activity']&.dup || {}
    tool_activity.merge!(updates.deep_stringify_keys)

    update!(
      metadata: metadata.merge('tool_activity' => tool_activity)
    )
  end

  # Delete keys from tool_activity (e.g., clear display_message)
  #
  # @param keys [Array<String, Symbol>] Keys to delete
  # @return [Boolean] true if update succeeded
  #
  # Example:
  #   message.delete_tool_activity_fields([:display_message, :error])
  def delete_tool_activity_fields(keys)
    tool_activity = metadata['tool_activity']&.dup || {}
    keys.each { |key| tool_activity.delete(key.to_s) }

    update!(
      metadata: metadata.merge('tool_activity' => tool_activity)
    )
  end

  private

  def agentable_belongs_to_user
    if agentable && agentable.user_id != user_id
      errors.add(:agentable, 'must belong to the same user')
    end
  end

  def content_or_metadata_present
    if content.blank? && metadata.blank?
      errors.add(:base, 'Either content or metadata must be present')
    end
  end

  def auto_generate_content
    return unless tool? && content.blank?
    
    self.content = generate_tool_content
  end

  def generate_tool_content
    if metadata['note_reference'].present?
      "Note created"
    elsif metadata['tool_activity'].present?
      tool_name = metadata.dig('tool_activity', 'name')
      tool_status = metadata.dig('tool_activity', 'status') || 'in_progress'
      
      # Simple content - not displayed to users (they see tool cells)
      "Tool: #{tool_name} (#{tool_status})"
    else
      "System message"
    end
  end

  def stream_to_clients
    Rails.logger.debug("[ThreadMessage] Streaming message id=#{id} to channel=#{stream_channel}")
    
    Streams::Broker.publish(
      stream_channel,
      event: 'message',
      data: {
        id: id,
        content: content,
        source: source,
        metadata: metadata,
        created_at: created_at.iso8601,
        renders_as_cell: renders_as_cell?
      }
    )
  rescue => e
    Rails.logger.error("[ThreadMessage] Failed to stream message id=#{id}: #{e.message}")
    # Don't raise - message creation should succeed even if streaming fails
  end

  def is_send_message_tool?
    metadata.dig('tool_activity', 'name') == 'send_message'
  end
end
