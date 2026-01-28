# frozen_string_literal: true

module Tools
  module System
    class CreateNote < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'create_note',
          description: 'Create a quick update note (150-250 words). Must match editorial voice in system prompt - natural, specific, no "Found this..." openings. See examples in voice guide above. [Visible - user sees note card]',
          params_hint: 'content (required, 150-250 words, match editorial voice), title (required, specific)'
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            content: { type: 'string' },
            title: { type: 'string' }
          },
          required: ['content'],
          additionalProperties: false
        }
      end

      # Params:
      # - content: String (required)
      # - title: String (optional) - extracted from content if not provided
      # Returns: { success: true, note_id: Integer }
      def execute(content:, title: nil)
        # Emit progress update with note preview
        emit_tool_progress("Creating note...", data: {
          note_preview: content.to_s.truncate(100),
          status: 'creating'
        })

        note = @user.notes.create!(
          goal: @goal,
          title: title.present? ? title.to_s : nil,
          content: content.to_s,
          source: :agent
        )

        # Emit completion update with note content for the specialized NoteToolCell
        emit_tool_completion("Note saved with #{note.content.length} characters", data: {
          note_id: note.id,
          title: note.title,
          content: note.content,
          content_length: note.content.length,
          status: 'created'
        })

        # If called from a task, also send a message to the goal's thread
        # Use the same tool_activity format so it displays the same way
        if @task && @goal
          ThreadMessage.create!(
            user: @user,
            agentable: @goal,
            source: :agent,
            message_type: :tool,
            tool_activity_id: "note_#{note.id}",  # Set column for efficient queries
            metadata: {
              tool_activity: {
                id: "note_#{note.id}",
                name: 'create_note',
                status: 'completed',
                data: {
                  note_id: note.id,
                  title: note.title,
                  content: note.content,
                  status: 'created'
                }
              }
            }
          )
        end

        # Broadcast to global stream for real-time UI updates
        begin
          global_channel = Streams::Channels.global_for_user(user: @user)
          Streams::Broker.publish(
            global_channel,
            event: 'note_created',
            data: {
              note_id: note.id,
              title: note.title,
              content: note.content.to_s.truncate(200),
              goal_id: @goal&.id,
              created_at: note.created_at.iso8601,
              source: 'agent'
            }
          )

          # Also broadcast goal_updated so iOS refreshes counts
          if @goal
            Streams::Broker.publish(
              global_channel,
              event: 'goal_updated',
              data: {
                goal_id: @goal.id,
                title: @goal.title,
                status: @goal.status
              }
            )
          end
        rescue => e
          Rails.logger.error("[CreateNote] Failed to broadcast to global stream: #{e.message}")
          # Don't fail the operation if broadcast fails
        end

        {
          success: true,
          note_id: note.id,
          title: note.title,
          content: note.content,
          observation: "Created note with #{note.content.length} characters. Note has been saved and is available for future reference."
        }
      end
    end
  end
end
