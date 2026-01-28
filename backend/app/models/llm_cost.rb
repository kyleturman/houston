class LlmCost < ApplicationRecord
  belongs_to :user
  belongs_to :agentable, polymorphic: true, optional: true
  
  validates :provider, :model, :input_tokens, :output_tokens, :cost, presence: true
  validates :input_tokens, :output_tokens, numericality: { greater_than_or_equal_to: 0 }
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
  
  scope :for_user, ->(user) { where(user: user) }
  scope :for_agentable, ->(agentable) { where(agentable: agentable) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Calculate total cost for a user
  def self.total_for_user(user)
    where(user: user).sum(:cost)
  end
  
  # Calculate total cost for an agentable
  def self.total_for_agentable(agentable)
    where(agentable: agentable).sum(:cost)
  end
  
  # Format cost for display
  def formatted_cost
    self.class.format_cost(cost)
  end
  
  # Format any cost value
  def self.format_cost(amount)
    return "$0.00" if amount.nil? || amount.zero?
    
    if amount < 0.01
      "$#{format('%.6f', amount)}"
    else
      "$#{format('%.2f', amount)}"
    end
  end
end
