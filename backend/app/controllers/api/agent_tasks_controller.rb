# frozen_string_literal: true

class Api::AgentTasksController < Api::BaseController
  before_action :load_goal, only: [:index]
  before_action :load_task, only: [:show, :retry]

  def index
    tasks = current_user.agent_tasks
    tasks = tasks.where(goal_id: @goal.id) if @goal
    tasks = tasks.order(created_at: :desc)
    render json: AgentTaskSerializer.new(tasks).serializable_hash
  end

  def show
    render json: AgentTaskSerializer.new(@task).serializable_hash
  end

  def retry
    unless @task.paused?
      render json: { error: 'Task is not paused' }, status: :unprocessable_entity
      return
    end

    unless @task.retryable?
      render json: { error: 'Task has exceeded maximum retry attempts' }, status: :unprocessable_entity
      return
    end

    begin
      # Update task to active status and restart orchestrator
      @task.update!(status: :active)
      @task.start_orchestrator!
      
      Rails.logger.info("[AgentTasksController] Manual retry initiated for task #{@task.id} by user #{current_user.id}")
      
      render json: AgentTaskSerializer.new(@task.reload).serializable_hash
    rescue => e
      Rails.logger.error("[AgentTasksController] Failed to retry task #{@task.id}: #{e.message}")
      render json: { error: "Failed to retry task: #{e.message}" }, status: :internal_server_error
    end
  end

  private

  def load_goal
    @goal = current_user.goals.find_by(id: params[:goal_id])
    head :not_found unless @goal
  end

  def load_task
    @task = current_user.agent_tasks.find_by(id: params[:id])
    head :not_found unless @task
  end
end
