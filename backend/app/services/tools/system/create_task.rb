# frozen_string_literal: true

module Tools
  module System
    class CreateTask < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'create_task',
          description: 'Create a new task. Title should be SUBJECT-FOCUSED and ultra-concise (2-3 words, max 4). Examples: "Oakland pediatricians", "Baby toys", "Hiking trails" (NOT "Research Oakland pediatricians" or "Find baby toys"). MUST provide clear task instructions that incorporate any relevant context from learnings and notes - the task agent will not see this context, so include it directly in the instructions. [Visible - user sees task card]',
          params_hint: 'title (required, 2-4 words, subject-focused), instructions (REQUIRED - detailed task instructions)',
          completion_signal: true # This tool can complete the agent's work
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            title: { type: 'string' },
            instructions: { type: 'string' }
          },
          required: ['title', 'instructions'],
          additionalProperties: false
        }
      end

      # Params:
      # - title: String (required)
      # - instructions: String (REQUIRED)
      # Returns: { success: true, task_id: Integer }
      def execute(title:, instructions:)
        raise ArgumentError, 'instructions cannot be blank' if instructions.to_s.strip.empty?

        # Normalize spacing in instructions (fixes LLM output issues like "baby4months" -> "baby 4 months")
        normalized_instructions = normalize_text_spacing(instructions.to_s)

        # Emit progress update
        emit_tool_progress("Creating task...")

        # Determine parent: Goal or UserAgent (polymorphic)
        parent_goal = @agentable.is_a?(Goal) ? @agentable : nil
        parent_taskable = @agentable.is_a?(UserAgent) ? @agentable : nil

        # DEDUPLICATION: Check for existing active task with same title (created in last 10 min)
        # Prevents duplicate tasks from stuck sessions or rapid retries
        # 10 min window catches real duplicates (typically 3-9 min apart) while allowing
        # legitimate re-attempts after task failures (usually 30+ min later)
        existing_task = @user.agent_tasks
          .where(taskable: parent_taskable, goal: parent_goal)
          .where(title: title.to_s)
          .where(status: [:active, :paused])
          .where('created_at >= ?', 10.minutes.ago)
          .first

        if existing_task
          Rails.logger.info("[CreateTask] Found existing task '#{title}' (id: #{existing_task.id}), returning it instead of creating duplicate")
          emit_tool_completion("Task already exists: #{existing_task.title}")
          return {
            success: true,
            task_id: existing_task.id,
            task_title: existing_task.title,
            task_status: existing_task.status.to_s,
            observation: "Task '#{existing_task.title}' already exists and is #{existing_task.status}. No new task created.",
            deduplicated: true
          }
        end

        # Pass relevant context from parent to child task
        # This ensures feed_period and other context flows through task delegation
        inherited_context = extract_inheritable_context

        t = @user.agent_tasks.create!(
          goal: parent_goal,
          taskable: parent_taskable,
          title: title.to_s,
          instructions: normalized_instructions,
          status: :active,
          origin_tool_activity_id: @activity_id,
          context_data: inherited_context
        )

        # Registry will create ThreadMessage with tool_activity metadata
        # No need for separate task_status ThreadMessage

        # Orchestrator is started automatically by AgentTask's after_create callback

        # Emit completion update
        emit_tool_completion("Created task: #{t.title}")

        # Broadcast to global stream for real-time UI updates
        begin
          global_channel = Streams::Channels.global_for_user(user: @user)
          Streams::Broker.publish(
            global_channel,
            event: 'task_created',
            data: {
              task_id: t.id,
              title: t.title,
              instructions: t.instructions.to_s.truncate(200),
              goal_id: t.goal_id,
              taskable_type: t.taskable_type,
              taskable_id: t.taskable_id,
              status: t.status.to_s,
              created_at: t.created_at.iso8601
            }
          )

          # Also broadcast goal_updated so iOS refreshes counts
          if t.goal_id
            goal = Goal.find_by(id: t.goal_id)
            if goal
              Streams::Broker.publish(
                global_channel,
                event: 'goal_updated',
                data: {
                  goal_id: goal.id,
                  title: goal.title,
                  status: goal.status
                }
              )
            end
          end
        rescue => e
          Rails.logger.error("[CreateTask] Failed to broadcast to global stream: #{e.message}")
          # Don't fail the operation if broadcast fails
        end

        {
          success: true,
          task_id: t.id,
          task_title: t.title,
          task_status: t.status.to_s,
          observation: "Created task '#{t.title}' with priority #{t.priority}. Task agent has been started and will begin working on this task."
        }
      end

      private

      # Extract context fields that should be inherited by child tasks.
      # This ensures feed_period and other context flows through task delegation.
      #
      # NOTE: 'type' is mapped to 'origin_type' — it controls orchestrator execution mode
      # (e.g. 'feed_generation', 'agent_check_in') and must not propagate as 'type' or
      # the child task's orchestrator will misidentify its execution mode.
      # 'origin_type' is safe metadata about where this task came from.
      def extract_inheritable_context
        return {} unless @context.present?

        inherited = @context.slice('feed_period', 'time_of_day', 'scheduled').compact

        # Preserve origin as metadata (not as orchestrator execution mode)
        inherited['origin_type'] = @context['type'] if @context['type'].present?

        inherited
      end

      # Normalize text spacing to fix common LLM output issues
      # Fixes patterns like "baby4months" -> "baby 4 months", "December2025" -> "December 2025"
      def normalize_text_spacing(text)
        return text unless text.is_a?(String)

        text
          .gsub(/([a-z])(\d)/, '\1 \2')  # lowercase followed by digit: "baby4months" -> "baby 4months"
          .gsub(/(\d)([a-z])/i, '\1 \2') # digit followed by letter: "4months" -> "4 months"
          .gsub(/([a-z])([A-Z])/, '\1 \2') # camelCase: "DecemberChristmas" -> "December Christmas"
      end
    end
  end
end
