# frozen_string_literal: true

class AgentHistory < ApplicationRecord
  # Polymorphic association - belongs to Goal, AgentTask, or UserAgent
  belongs_to :agentable, polymorphic: true
  has_many :thread_messages, dependent: :destroy

  # Encrypt sensitive fields
  encrypts :agent_history
  encrypts :summary

  # Validations
  validates :agent_history, presence: true
  validates :summary, presence: true
  validates :completed_at, presence: true

  # Callbacks
  before_destroy :clear_related_task_summaries

  # Scopes
  scope :recent, -> { order(completed_at: :desc) }
  scope :for_agentable, ->(agentable) { where(agentable: agentable) }
  scope :with_messages, -> { includes(:thread_messages) }
  scope :paginated, ->(page, per_page = 10) { offset((page - 1) * per_page).limit(per_page) }

  private

  # When an agent history is deleted, clean up tasks created during that session
  # - Completed tasks: delete entirely (they're agent scratch work fully contained in the session)
  # - Incomplete tasks: just clear result_summary (user might still want to complete them)
  def clear_related_task_summaries
    return unless started_at && completed_at

    tasks_scope = case agentable
    when Goal
      AgentTask.where(goal_id: agentable_id)
    when UserAgent
      AgentTask.where(user_id: agentable.user_id, goal_id: nil)
    else
      AgentTask.none
    end

    session_tasks = tasks_scope.where('created_at >= ? AND created_at <= ?', started_at, completed_at)

    # Delete completed tasks entirely - they're agent scratch work
    deleted_count = session_tasks.where(status: :completed).delete_all

    # For incomplete tasks, just clear the result_summary
    cleared_count = session_tasks
      .where.not(status: :completed)
      .where.not(result_summary: nil)
      .update_all(result_summary: nil)

    if deleted_count.positive? || cleared_count.positive?
      Rails.logger.info("[AgentHistory] Deleted #{deleted_count} completed tasks, cleared summary on #{cleared_count} incomplete tasks for history##{id}")
    end
  end
end
