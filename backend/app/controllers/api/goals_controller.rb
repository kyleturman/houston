# frozen_string_literal: true

class Api::GoalsController < Api::BaseController
  before_action :set_goal, only: %i[show update destroy agent_reset]

  def index
    goals = current_user.goals.order(created_at: :desc)
    render json: GoalSerializer.new(goals).serializable_hash
  end

  def show
    render json: GoalSerializer.new(@goal).serializable_hash
  end

  def create
    begin
      goal = Goal.create_with_agent!(
        user: current_user,
        title: goal_params[:title],
        description: goal_params[:description],
        agent_instructions: goal_params[:agent_instructions],
        learnings: goal_params[:learnings],
        enabled_mcp_servers: goal_params[:enabled_mcp_servers],
        accent_color: goal_params[:accent_color]
      )

      # Broadcast goal_created event to global stream
      publish_lifecycle_event('goal_created', goal)

      render json: GoalSerializer.new(goal).serializable_hash, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue ArgumentError => e
      render json: { errors: [e.message] }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error("[GoalsController] Error creating goal: #{e.class}: #{e.message}")
      render json: { errors: [e.message] }, status: :unprocessable_entity
    end
  end

  def update
    params_to_update = goal_params.to_h

    # Format learnings if provided (convert strings to dict format)
    if params_to_update[:learnings].present?
      params_to_update[:learnings] = params_to_update[:learnings].map do |learning|
        if learning.is_a?(String)
          { content: learning, created_at: Time.current.iso8601 }
        else
          learning
        end
      end
    end

    if @goal.update(params_to_update)
      # Broadcast goal_updated event to global stream
      publish_lifecycle_event('goal_updated', @goal)

      render json: GoalSerializer.new(@goal).serializable_hash
    else
      render json: { errors: @goal.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    goal_id = @goal.id
    goal_title = @goal.title

    @goal.destroy

    # Broadcast goal_archived event to global stream
    publish_lifecycle_event('goal_archived', nil, { goal_id: goal_id, title: goal_title })

    head :no_content
  end

  # POST /api/goals/:id/agent_reset
  # Clears agent-related state for a goal for debugging: thread messages,
  # tasks (and their thread messages), and removes queued orchestrator jobs.
  # Notes are NOT deleted.
  def agent_reset
    ActiveRecord::Base.transaction do
      # Delete thread messages tied to this goal and its tasks
      agentables = [@goal] + @goal.agent_tasks.to_a
      ThreadMessage.where(agentable: agentables).delete_all

      # Delete all tasks (notes remain intact per comment)
      @goal.agent_tasks.destroy_all
      
      # Clear goal's agent state (llm_history only)
      # Note: learnings are preserved as they contain valuable accumulated knowledge
      @goal.update!(llm_history: [])
    end

    # Purge any queued Sidekiq jobs for this goal/tasks (default queue, scheduled, and retry)
    begin
      purge_sidekiq_jobs_for_agentables([@goal])
    rescue => e
      Rails.logger.warn("[GoalsController#agent_reset] Sidekiq purge failed: #{e.class}: #{e.message}")
    end

    render json: { ok: true }
  end

  # POST /api/goals/reorder
  # Updates display order for multiple goals
  # Expects: { goal_ids: ["1", "3", "2"] } - array of goal IDs in desired order
  def reorder
    goal_ids = params[:goal_ids]

    unless goal_ids.is_a?(Array) && goal_ids.all? { |id| id.to_s.present? }
      return render json: { error: 'goal_ids must be an array of IDs' }, status: :unprocessable_entity
    end

    # Verify all goals belong to current user
    user_goal_ids = current_user.goals.pluck(:id).map(&:to_s)
    invalid_ids = goal_ids - user_goal_ids

    if invalid_ids.any?
      return render json: { error: "Invalid goal IDs: #{invalid_ids.join(', ')}" }, status: :forbidden
    end

    # Update the order
    Goal.update_display_order(goal_ids)

    head :no_content
  end

  private

  def set_goal
    @goal = current_user.goals.find(params[:id])
  end

  def goal_params
    params.require(:goal).permit(:title, :description, :status, :accent_color, :agent_instructions, learnings: [], enabled_mcp_servers: [])
  end

  # Remove scheduled/queued orchestrator jobs for the provided agentables
  # Orchestrator jobs now take arguments: [agentable_type, agentable_id]
  def purge_sidekiq_jobs_for_agentables(agentables)
    require 'sidekiq/api'
    targets = agentables.flat_map do |a|
      if a.is_a?(Goal)
        [[a.class.name, a.id]] + a.agent_tasks.map { |t| [t.class.name, t.id] }
      else
        [[a.class.name, a.id]]
      end
    end

    # Queues
    Sidekiq::Queue.all.each do |q|
      q.each do |job|
        begin
          if job.klass&.start_with?('Agents::') && job.args.is_a?(Array)
            arg_type, arg_id = job.args
            if targets.include?([arg_type, arg_id])
              job.delete
            end
          end
        rescue => _e
          # ignore individual job errors
        end
      end
    end

    # Scheduled
    Sidekiq::ScheduledSet.new.each do |job|
      begin
        if job.klass&.start_with?('Agents::') && job.args.is_a?(Array)
          arg_type, arg_id = job.args
          job.delete if targets.include?([arg_type, arg_id])
        end
      rescue => _e; end
    end

    # Retries
    Sidekiq::RetrySet.new.each do |job|
      begin
        if job.klass&.start_with?('Agents::') && job.args.is_a?(Array)
          arg_type, arg_id = job.args
          job.delete if targets.include?([arg_type, arg_id])
        end
      rescue => _e; end
    end
  end

  # Publish lifecycle event to global stream
  # @param event_name [String] The event name (e.g., 'goal_created')
  # @param goal [Goal, nil] The goal object (nil for delete events)
  # @param extra_data [Hash] Additional data to include in the event
  def publish_lifecycle_event(event_name, goal, extra_data = {})
    channel = Streams::Channels.global_for_user(user: current_user)

    data = if goal
      {
        goal_id: goal.id,
        title: goal.title,
        description: goal.description,
        status: goal.status,
        accent_color: goal.accent_color,
        created_at: goal.created_at&.iso8601,
        updated_at: goal.updated_at&.iso8601
      }.merge(extra_data)
    else
      extra_data
    end

    Streams::Broker.publish(
      channel,
      event: event_name,
      data: data
    )

    Rails.logger.info("[GoalsController] Published #{event_name} to global stream for user #{current_user.id}")
  rescue => e
    # Don't fail the request if SSE publishing fails
    Rails.logger.error("[GoalsController] Failed to publish #{event_name}: #{e.message}")
  end
end

