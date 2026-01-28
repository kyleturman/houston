# frozen_string_literal: true

module Tools
  module System
    class ManageLearning < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'manage_learning',
          description: 'Manage durable facts about the user. Learnings should be SHORT (1 sentence), DURABLE (won\'t become stale), and USER-CENTRIC (preferences, patterns, constraints). Use notes for longer content or temporal info. [Silent - user won\'t see this directly]',
          params_hint: 'action (add/update/remove), content, learning_id (for update/remove)',
          is_user_facing: false # Internal memory operation, no user-visible artifact
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            action: { type: 'string', enum: ['add', 'update', 'remove'] },
            content: { type: 'string' },
            learning_id: { type: 'string' }
          },
          required: ['action'],
          additionalProperties: false
        }
      end

      # Params:
      # - action: String (required) - 'add', 'update', or 'remove'
      # - content: String (required for add/update) - The learning content
      # - learning_id: String (required for update/remove) - ID of existing learning
      # Returns: { success: true/false, learning_id: String, observation: String }
      def execute(action:, content: nil, learning_id: nil)
        action = action.to_s.downcase.strip
        
        # Validate action
        unless %w[add update remove].include?(action)
          return { success: false, error: 'Action must be add, update, or remove' }
        end

        # Determine where to save: Goal gets its own learnings, Task saves to parent goal, UserAgent saves to itself
        learning_target = @agentable.associated_goal || @agentable
        
        case action
        when 'add'
          handle_add(learning_target, content)
        when 'update'
          handle_update(learning_target, learning_id, content)
        when 'remove'
          handle_remove(learning_target, learning_id)
        end
      end

      private

      def handle_add(target, content)
        return { success: false, error: 'Content is required for add action' } if content.blank?
        
        content = content.to_s.strip
        
        # Add the learning
        new_learning_id = target.add_learning(content)

        # Broadcast goal_updated so iOS refreshes
        publish_goal_updated(target) if target.is_a?(Goal)

        {
          success: true,
          learning_id: new_learning_id,
          observation: "Added learning: '#{content[0..100]}#{'...' if content.length > 100}'. This insight will be remembered for future reference."
        }
      rescue => e
        { success: false, error: "Failed to add learning: #{e.message}" }
      end

      def handle_update(target, learning_id, content)
        return { success: false, error: 'Learning ID is required for update action' } if learning_id.blank?
        return { success: false, error: 'Content is required for update action' } if content.blank?
        
        # Find existing learning to show what changed
        existing = target.find_learning(learning_id)
        return { success: false, error: "Learning not found with ID: #{learning_id}" } unless existing
        
        # Update the learning
        success = target.update_learning(learning_id, content: content&.strip)
        
        if success
          # Broadcast goal_updated so iOS refreshes
          publish_goal_updated(target) if target.is_a?(Goal)

          {
            success: true,
            learning_id: learning_id,
            observation: "Updated learning: Was '#{existing['content'] || existing[:content]}', now reflects new information."
          }
        else
          { success: false, error: "Failed to update learning with ID: #{learning_id}" }
        end
      rescue => e
        { success: false, error: "Failed to update learning: #{e.message}" }
      end

      def handle_remove(target, learning_id)
        return { success: false, error: 'Learning ID is required for remove action' } if learning_id.blank?
        
        # Find existing learning to show what was removed
        existing = target.find_learning(learning_id)
        return { success: false, error: "Learning not found with ID: #{learning_id}" } unless existing
        
        # Remove the learning
        success = target.remove_learning(learning_id)
        
        if success
          # Broadcast goal_updated so iOS refreshes
          publish_goal_updated(target) if target.is_a?(Goal)

          {
            success: true,
            learning_id: learning_id,
            observation: "Removed outdated/incorrect learning: '#{existing['content'] || existing[:content]}'. This information is no longer in memory."
          }
        else
          { success: false, error: "Failed to remove learning with ID: #{learning_id}" }
        end
      rescue => e
        { success: false, error: "Failed to remove learning: #{e.message}" }
      end

      def publish_goal_updated(goal)
        channel = Streams::Channels.global_for_user(user: @user)
        Streams::Broker.publish(
          channel,
          event: 'goal_updated',
          data: {
            goal_id: goal.id,
            title: goal.title,
            status: goal.status,
            updated_at: Time.current.iso8601
          }
        )
      end
    end
  end
end
