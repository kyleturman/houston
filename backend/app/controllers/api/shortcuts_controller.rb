# frozen_string_literal: true

module Api
  # Controller for handling Siri/Shortcuts/App Intents requests
  # These endpoints are designed for fire-and-forget agent queries that complete in background
  # Notifications are sent when queries complete
  class ShortcutsController < BaseController
    before_action :authenticate_user!, only: [:agent_query]

    # POST /api/shortcuts/agent_query
    # Send a fire-and-forget agent query from Siri/Shortcuts
    # Query runs in background, notification sent when complete
    #
    # Body:
    #   {
    #     "query": "What tasks do I have today?",
    #     "goal_id": "123" (optional)
    #   }
    #
    # Returns immediately with 202 Accepted:
    #   {
    #     "success": true,
    #     "message": "Query accepted, you'll be notified when complete",
    #     "task_id": "456"
    #   }
    def agent_query
      query = params[:query]
      goal_id = params[:goal_id]

      if query.blank?
        render json: { error: "query parameter is required" }, status: :unprocessable_entity
        return
      end

      # Find goal if specified
      goal = nil
      if goal_id.present?
        goal = current_user.goals.find_by(id: goal_id)
        unless goal
          render json: { error: "Goal not found" }, status: :not_found
          return
        end
      end

      # Create agent task for the query
      task = AgentTask.create!(
        user: current_user,
        goal: goal,
        title: query.truncate(100),
        instructions: query,
        status: :active,
        priority: :high
      )

      Rails.logger.info("[ShortcutsController] Created task #{task.id} for user #{current_user.id} from App Intent")

      # Queue orchestrator job
      Agents::Orchestrator.perform_async('AgentTask', task.id)

      render json: {
        success: true,
        message: "Query accepted, you'll be notified when complete",
        task_id: task.id.to_s,
        goal_id: goal&.id&.to_s
      }, status: :accepted
    end
  end
end
