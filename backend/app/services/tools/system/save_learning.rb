# frozen_string_literal: true

module Tools
  module System
    class SaveLearning < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'save_learning',
          description: 'Save a learning or insight to the agent\'s memory for future reference. Use when discovering important patterns, solutions, or knowledge that should be remembered. [Silent - user won\'t see this directly]',
          params_hint: 'content (required)',
          is_user_facing: false # Internal memory operation, no user-visible artifact
        )
      end

      # Params:
      # - content: String (required) - The learning or insight to save
      # Returns: { success: true, learning_id: String }
      def execute(content:)
        learning_content = content.to_s.strip
        return { success: false, error: 'Learning content cannot be empty' } if learning_content.blank?

        # Determine where to save: Goal gets its own learnings, Task saves to parent goal, UserAgent saves to itself
        learning_target = @agentable.associated_goal || @agentable
        
        # Save the learning
        learning_target.add_learning(learning_content)

        { 
          success: true, 
          learning_id: SecureRandom.uuid,
          observation: "Saved learning: '#{learning_content[0..100]}#{'...' if learning_content.length > 100}'. This insight has been added to your memory for future reference."
        }
      end
    end
  end
end
