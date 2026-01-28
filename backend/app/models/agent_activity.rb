# frozen_string_literal: true

class AgentActivity < ApplicationRecord
  # Polymorphic association - belongs to Goal, AgentTask, or UserAgent
  belongs_to :agentable, polymorphic: true
  belongs_to :goal, optional: true

  # Validations
  validates :agent_type, presence: true, inclusion: { in: %w[goal task user_agent] }
  validates :started_at, presence: true
  validates :completed_at, presence: true
  validates :input_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :output_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :cost_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tool_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :iterations, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :recent, -> { order(completed_at: :desc) }
  scope :for_agentable, ->(agentable) { where(agentable: agentable) }
  scope :for_goal, ->(goal_id) { where(goal_id: goal_id) }
  scope :by_agent_type, ->(type) { where(agent_type: type) }
  scope :natural_completions, -> { where(natural_completion: true) }

  # Scope to filter activities belonging to a specific user
  # Joins the polymorphic agentable to find activities owned by the user
  scope :for_user, ->(user) {
    joins('LEFT JOIN goals ON agent_activities.goal_id = goals.id')
    .joins(<<~SQL.squish)
      LEFT JOIN agent_tasks ON
        agent_activities.agentable_type = 'AgentTask' AND
        agent_activities.agentable_id = agent_tasks.id
    SQL
    .joins(<<~SQL.squish)
      LEFT JOIN user_agents ON
        agent_activities.agentable_type = 'UserAgent' AND
        agent_activities.agentable_id = user_agents.id
    SQL
    .where('goals.user_id = :user_id OR agent_tasks.user_id = :user_id OR user_agents.user_id = :user_id', user_id: user.id)
    .distinct
  }

  # Calculated fields
  def duration_seconds
    return 0 unless started_at && completed_at
    (completed_at - started_at).to_i
  end

  def cost_dollars
    cost_cents / 100.0
  end

  def formatted_cost
    "$#{format('%.4f', cost_dollars)}"
  end

  def total_tokens
    input_tokens + output_tokens
  end

  # Human-readable tool summary
  def tools_summary
    return "No tools used" if tool_count.zero?

    tool_names = (tools_called || []).map { |t| t.is_a?(Hash) ? t['name'] || t[:name] : t }.compact
    return "#{tool_count} tool#{tool_count > 1 ? 's' : ''}" if tool_names.empty?

    tool_names.first(3).join(', ') + (tool_count > 3 ? ", +#{tool_count - 3} more" : "")
  end

  def agent_type_label
    case agent_type
    when 'goal'
      goal_name = goal&.title || agentable&.title
      goal_name.present? ? "#{goal_name} agent" : 'Goal agent'
    when 'task'
      goal_name = goal&.title
      goal_name.present? ? "#{goal_name} task" : 'User agent task'
    when 'user_agent'
      'User agent'
    else
      agent_type.titleize
    end
  end
end
