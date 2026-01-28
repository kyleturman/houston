# frozen_string_literal: true

class User < ApplicationRecord
  # Associations
  has_many :devices, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :agent_tasks, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_one :user_agent, dependent: :destroy
  has_many :llm_costs, dependent: :destroy
  has_many :user_mcp_connections, dependent: :destroy
  has_many :invite_tokens, dependent: :destroy

  # Encrypt PII fields
  # Note: email is NOT encrypted so admin can monitor users and costs on self-hosted server
  encrypts :name

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  # Role enum for user permissions
  enum :role, {
    user: 'user',   # Regular mobile app users
    admin: 'admin'  # Server admin(s)
  }, default: 'user'

  before_validation :downcase_email
  before_create :set_admin_if_first_user
  after_create :create_user_agent

  # Virtual attribute for timezone (inferred from device, not stored in DB)
  attr_accessor :timezone

  def user_agent
    super || create_user_agent!
  end

  # Helper method for timezone with fallback to default
  def timezone_or_default
    timezone.presence || 'America/Los_Angeles'
  end

  # Calculate total LLM cost from individual LlmCost records
  def total_llm_cost
    LlmCost.total_for_user(self)
  end

  # Format total cost for display
  def formatted_llm_cost
    LlmCost.format_cost(total_llm_cost)
  end

  private

  def downcase_email
    self.email = email.to_s.strip.downcase
  end

  # First user created becomes admin automatically (solves bootstrap problem)
  def set_admin_if_first_user
    self.role = :admin if User.count.zero?
  end

  def create_user_agent
    UserAgent.create!(user: self)
  rescue => e
    Rails.logger.error("[User] Failed to create UserAgent for user=#{id}: #{e.message}")
    # Don't fail user creation if UserAgent creation fails
  end
end
