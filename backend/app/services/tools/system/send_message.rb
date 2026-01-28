# frozen_string_literal: true

module Tools
  module System
    # SendMessage posts a message from the agent to the conversation thread
    # and publishes it on the SSE channel. This is fast (DB insert + Redis publish)
    # and avoids any LLM round-trip.
    class SendMessage < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'send_message',
          description: 'Communicate brief updates to the user. CRITICAL: ONE paragraph only (1-2 sentences, ~40 words max). You may use **bold** or *italic* for emphasis, but never use bullet points, lists, headers, or multiple paragraphs.',
          params_hint: 'text (required), references (optional), stream (optional)'
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            text: { type: 'string' }
          },
          required: ['text'],
          additionalProperties: false
        }
      end

      # Params:
      # - text: String (required)
      # - references: Hash (optional) -> { task_id:, note_id:, ... }
      def execute(text:, references: {})
        raise ArgumentError, 'text cannot be blank' if text.to_s.strip.empty?

        channel = Streams::Channels.for_agentable(agentable: @agentable)

        # NOTE: Text has already been streamed in real-time by Service.agent_call
        # as the LLM generated the tool parameters via input_json_delta events.
        # We just need to create the persisted ThreadMessage and signal completion.

        # Create ThreadMessage
        tm = ThreadMessage.create!(
          user: @user,
          agentable: @agentable,
          source: :agent,
          content: text,
          metadata: { references: references }
        )

        # Publish message event to trigger iOS refresh
        # This replaces the streaming message with the persisted ThreadMessage
        Streams::Broker.publish(channel, event: :message, data: { id: tm.id })

        {
          success: true,
          message_id: tm.id,
          observation: "Message sent to user: '#{text[0..100]}#{'...' if text.length > 100}'. User has been updated on your progress."
        }
      end
    end
  end
end
