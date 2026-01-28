# frozen_string_literal: true

class Goal < ApplicationRecord
  include Agentable

  # Associations
  belongs_to :user
  has_many :agent_tasks, dependent: :destroy
  has_many :notes, dependent: :destroy

  enum :status, { working: 0, waiting: 1, archived: 2 }

  # Scopes
  scope :active, -> { where.not(status: :archived) }

  # Default order by display_order
  default_scope { order(display_order: :asc, created_at: :asc) }

  # Goal-specific attributes
  attribute :learnings, :json, default: []
  attribute :enabled_mcp_servers, :json, default: []
  attribute :check_in_schedule, :json, default: nil

  # Encrypt sensitive fields
  encrypts :llm_history
  encrypts :description
  encrypts :agent_instructions
  encrypts :learnings
  encrypts :check_in_schedule

  validates :title, presence: true
  validates :status, presence: true

  # Set default status to waiting
  after_initialize :set_default_status, if: :new_record?

  # Clean up stale MCP server references before save
  before_save :sanitize_enabled_mcp_servers

  # Set display_order to end of list for new goals
  before_create :set_display_order

  def active?
    !archived?
  end

  # Create goal with agent setup - replaces Goals::SetupService
  def self.create_with_agent!(user:, title:, description: nil, agent_instructions: nil, learnings: nil, enabled_mcp_servers: nil, accent_color: nil)
    title = title.to_s.strip
    raise ArgumentError, 'Title cannot be blank' if title.blank?

    # Convert learnings to dict format if they're strings
    formatted_learnings = (learnings || []).map do |learning|
      if learning.is_a?(String)
        { content: learning, created_at: Time.current.iso8601 }
      else
        learning
      end
    end

    transaction do
      goal = user.goals.create!(
        title: title, 
        description: description,
        agent_instructions: agent_instructions,
        learnings: formatted_learnings,
        enabled_mcp_servers: enabled_mcp_servers || [],
        accent_color: accent_color, 
        status: :working
      )

      # Start orchestrator
      goal.start_orchestrator!
      
      Rails.logger.info("[Goal] Created goal=#{goal.id} with agent and started orchestrator")
      goal
    end
  end

  # Start the orchestrator for this goal
  def start_orchestrator!
    return unless can_execute?

    # Start immediately - async handles job queuing, no need for artificial delay
    job_id = Agents::Orchestrator.perform_async(self.class.name, id)
    set_orchestrator_job_id!(job_id)
    
    Rails.logger.info("[Goal] Started orchestrator for goal=#{id} job=#{job_id}")
    job_id
  end

  # Learning Management (Goal-specific)
  # Core methods (add_learning, update_learning, remove_learning, find_learning, learnings_as_xml) 
  # are defined in Agentable concern
  
  def relevant_learnings(limit: 5)
    (learnings || []).last(limit).reverse
  end

  # Check-in schedule helpers
  def has_check_in_schedule?
    check_in_schedule.present? && check_in_schedule['frequency'].present? && check_in_schedule['frequency'] != 'none'
  end

  # Business logic: when does this goal need search_notes tool?
  def requires_search_tool?
    notes.count > Note::SEARCH_TOOL_THRESHOLD
  end

  # Update display order for multiple goals
  def self.update_display_order(goal_ids_in_order)
    transaction do
      goal_ids_in_order.each_with_index do |goal_id, index|
        where(id: goal_id).update_all(display_order: index)
      end
    end
  end

  private

  def set_default_status
    self.status ||= :waiting
  end

  def set_display_order
    # Set to the end of the user's goal list if not set
    self.display_order ||= user.goals.unscoped.where(user_id: user_id).maximum(:display_order).to_i + 1
  end

  def sanitize_enabled_mcp_servers
    return if enabled_mcp_servers.blank?

    valid = McpServer.valid_names
    cleaned = enabled_mcp_servers.select { |name| valid.include?(name.downcase) }

    if cleaned != enabled_mcp_servers
      Rails.logger.info("[Goal] Cleaned stale MCP servers from goal #{id}: #{enabled_mcp_servers - cleaned}")
      self.enabled_mcp_servers = cleaned
    end
  end
end
