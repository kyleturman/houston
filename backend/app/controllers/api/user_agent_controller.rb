# frozen_string_literal: true

class Api::UserAgentController < Api::BaseController
  # GET /api/user_agent
  # Returns user agent data including learnings
  def show
    user_agent = current_user.user_agent

    return render json: { error: 'User agent not found' }, status: :not_found unless user_agent

    render json: UserAgentSerializer.new(user_agent).serializable_hash
  end

  # PATCH /api/user_agent
  # Updates user agent attributes (currently just learnings)
  def update
    user_agent = current_user.user_agent

    return render json: { error: 'User agent not found' }, status: :not_found unless user_agent

    params_to_update = user_agent_params.to_h

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

    if user_agent.update(params_to_update)
      render json: UserAgentSerializer.new(user_agent).serializable_hash
    else
      render json: { errors: user_agent.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/user_agent/reset
  # Clears agent-related state for the user agent: thread messages and LLM history.
  def reset
    user_agent = current_user.user_agent
    
    return render json: { error: 'User agent not found' }, status: :not_found unless user_agent

    ActiveRecord::Base.transaction do
      # Delete thread messages tied to this user agent
      ThreadMessage.where(agentable: user_agent).delete_all
      
      # Clear LLM history
      user_agent.update!(llm_history: [])
    end

    # Purge any queued Sidekiq jobs for this user agent
    begin
      purge_sidekiq_jobs_for_agentables([user_agent])
    rescue => e
      Rails.logger.warn("[UserAgentController#reset] Sidekiq purge failed: #{e.class}: #{e.message}")
    end

    render json: { ok: true }
  end

  private

  def user_agent_params
    params.require(:user_agent).permit(learnings: [])
  end

  def purge_sidekiq_jobs_for_agentables(agentables)
    require 'sidekiq/api'
    agentable_ids = agentables.map(&:id)
    agentable_types = agentables.map { |a| a.class.name }.uniq

    # Scan default queue
    Sidekiq::Queue.new.each do |job|
      if job.klass == 'Agents::Orchestrator' &&
         agentable_types.include?(job.args[0]) &&
         agentable_ids.include?(job.args[1])
        job.delete
      end
    end

    # Scan scheduled set
    Sidekiq::ScheduledSet.new.each do |job|
      if job.klass == 'Agents::Orchestrator' &&
         agentable_types.include?(job.args[0]) &&
         agentable_ids.include?(job.args[1])
        job.delete
      end
    end

    # Scan retry set
    Sidekiq::RetrySet.new.each do |job|
      if job.klass == 'Agents::Orchestrator' &&
         agentable_types.include?(job.args[0]) &&
         agentable_ids.include?(job.args[1])
        job.delete
      end
    end
  end
end
