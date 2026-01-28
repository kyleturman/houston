# frozen_string_literal: true

class UserAgent < ApplicationRecord
  include Agentable

  # Associations
  belongs_to :user
  has_many :agent_tasks, as: :taskable, dependent: :destroy
  has_many :feed_insights, dependent: :destroy

  # UserAgent-specific attributes
  attribute :learnings, :json, default: []

  # Encrypt sensitive fields
  encrypts :llm_history
  encrypts :learnings

  validates :user_id, presence: true, uniqueness: true

  # Setup feed insight schedules after creation
  after_create :setup_feed_schedules

  # Learning Management
  # Core methods (add_learning, update_learning, remove_learning, find_learning, learnings_as_xml) 
  # are defined in Agentable concern
  
  def relevant_learnings(limit: 10)
    (learnings || []).last(limit).reverse
  end

  # Start the orchestrator for this user agent
  def start_orchestrator!
    return unless can_execute?

    # Use the unified Orchestrator (same as Goal and AgentTask)
    job_id = Agents::Orchestrator.perform_in(rand(1..5).seconds, self.class.name, id)
    set_orchestrator_job_id!(job_id)

    Rails.logger.info("[UserAgent] Started orchestrator for user_agent=#{id} job=#{job_id}")
    job_id
  end

  private

  # Setup 3 daily feed insight generation jobs (morning, afternoon, evening)
  def setup_feed_schedules
    scheduler = Feeds::InsightScheduler.new(self)
    scheduler.schedule_all!
    Rails.logger.info("[UserAgent] Setup feed schedules for user_agent=#{id}")
  rescue StandardError => e
    Rails.logger.error("[UserAgent] Failed to setup feed schedules for user_agent=#{id}: #{e.message}")
    # Don't fail UserAgent creation if scheduling fails
  end
end
