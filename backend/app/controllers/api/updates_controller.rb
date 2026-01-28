# frozen_string_literal: true

module Api
  # Returns all updates since a given timestamp
  # Used by background refresh for efficient polling
  class UpdatesController < BaseController
    before_action :authenticate_user!

    # GET /api/updates/since/:timestamp
    # Returns all tasks, notes, and goals created or updated since timestamp
    #
    # Params:
    #   - timestamp: ISO8601 timestamp (e.g., "2025-11-04T12:34:56Z")
    #
    # Returns:
    #   {
    #     "tasks": [...],
    #     "notes": [...],
    #     "goals": [...],
    #     "timestamp": "2025-11-04T15:45:30Z"
    #   }
    def since
      timestamp_param = params[:timestamp]

      if timestamp_param.blank?
        render json: { error: 'timestamp parameter is required' }, status: :unprocessable_entity
        return
      end

      begin
        since_time = Time.parse(timestamp_param)
      rescue ArgumentError
        render json: { error: 'Invalid timestamp format (use ISO8601)' }, status: :unprocessable_entity
        return
      end

      Rails.logger.info("[UpdatesController] Fetching updates since #{since_time} for user #{current_user.id}")

      # Fetch updated tasks
      tasks = current_user.agent_tasks
                          .where('updated_at > ?', since_time)
                          .order(updated_at: :desc)
                          .limit(50)

      # Fetch updated notes
      notes = current_user.notes
                          .where('updated_at > ?', since_time)
                          .order(updated_at: :desc)
                          .limit(50)

      # Fetch updated goals
      goals = current_user.goals
                          .where('updated_at > ?', since_time)
                          .order(updated_at: :desc)
                          .limit(50)

      # Serialize resources (reuse existing serializers)
      render json: {
        tasks: tasks.map { |task| serialize_task(task) },
        notes: notes.map { |note| serialize_note(note) },
        goals: goals.map { |goal| serialize_goal(goal) },
        timestamp: Time.now.iso8601
      }
    end

    private

    def serialize_task(task)
      {
        id: task.id.to_s,
        type: 'agent_task',
        attributes: {
          title: task.title,
          status: task.status,
          priority: task.priority,
          goal_id: task.goal_id&.to_s,
          goal_title: task.goal&.title,
          created_at: task.created_at.iso8601,
          updated_at: task.updated_at.iso8601
        }
      }
    end

    def serialize_note(note)
      {
        id: note.id.to_s,
        type: 'note',
        attributes: {
          content: note.content,
          source: note.source,
          goal_id: note.goal_id&.to_s,
          created_at: note.created_at.iso8601,
          updated_at: note.updated_at.iso8601
        }
      }
    end

    def serialize_goal(goal)
      {
        id: goal.id.to_s,
        type: 'goal',
        attributes: {
          title: goal.title,
          status: goal.status,
          accent_color: goal.accent_color,
          created_at: goal.created_at.iso8601,
          updated_at: goal.updated_at.iso8601
        }
      }
    end
  end
end
