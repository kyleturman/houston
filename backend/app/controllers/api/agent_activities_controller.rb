# frozen_string_literal: true

class Api::AgentActivitiesController < Api::BaseController
  # GET /api/agent_activities
  # Query params:
  #   - page: page number (default: 1)
  #   - per_page: items per page (default: 20, max: 100)
  #   - agent_type: filter by agent_type (optional: 'goal', 'task', 'user_agent')
  #   - goal_id: filter by goal_id (optional)
  def index
    # Pagination params
    page = [params[:page].to_i, 1].max
    per_page = [[params[:per_page].to_i, 1].max, 100].min
    per_page = 20 if per_page.zero?

    # Base scope - only user's agent activities
    scope = AgentActivity.for_user(current_user)
                         .includes(:goal, :agentable)

    # Optional filters
    scope = scope.by_agent_type(params[:agent_type]) if params[:agent_type].present?
    scope = scope.for_goal(params[:goal_id]) if params[:goal_id].present?

    # Order by most recent first
    scope = scope.recent

    # Calculate total and pagination metadata
    total = scope.count
    total_pages = (total.to_f / per_page).ceil
    offset = (page - 1) * per_page

    # Fetch page of activities
    activities = scope.limit(per_page).offset(offset)

    # Render with pagination metadata
    render json: {
      data: AgentActivitySerializer.new(activities).serializable_hash[:data],
      meta: {
        current_page: page,
        per_page: per_page,
        total_items: total,
        total_pages: total_pages,
        has_next_page: page < total_pages,
        has_prev_page: page > 1
      }
    }
  end

  # GET /api/agent_activities/:id
  def show
    activity = find_user_activity(params[:id])
    return render json: { error: 'Activity not found' }, status: :not_found unless activity

    render json: AgentActivitySerializer.new(activity).serializable_hash
  end

  private

  def find_user_activity(id)
    AgentActivity.for_user(current_user).find_by(id: id)
  end
end
