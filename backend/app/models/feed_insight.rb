# frozen_string_literal: true

class FeedInsight < ApplicationRecord
  belongs_to :user
  belongs_to :user_agent

  enum :insight_type, { reflection: 0, discovery: 1 }

  # Cast metadata as JSON and encrypt it (like Note model)
  attribute :metadata, :json, default: {}
  encrypts :metadata

  validates :insight_type, presence: true
  validates :metadata, presence: true

  # Scopes
  scope :recent, -> { where('created_at >= ?', 7.days.ago) }
  scope :for_context, ->(user_agent) {
    where(user_agent: user_agent)
      .where('created_at >= ?', 7.days.ago)
      .order(created_at: :desc)
  }

  # Auto-cleanup old insights (>7 days)
  def self.cleanup_old_insights
    deleted_count = where('created_at < ?', 7.days.ago).delete_all
    Rails.logger.info "[FeedInsight] Cleaned up #{deleted_count} old insights"
    deleted_count
  end

  # For feed display - returns the content in a display-ready format
  def display_content
    case insight_type
    when 'reflection'
      # Reflections have a prompt for the user
      metadata['prompt']
    when 'discovery'
      # Discoveries are links with title, summary, url, source
      {
        title: metadata['title'],
        summary: metadata['summary'],
        url: metadata['url'],
        source: metadata['source']
      }
    end
  end

  # For prompts - context to avoid duplication
  # Includes URLs for discoveries to prevent linking to the same content repeatedly
  def to_context_string
    case insight_type
    when 'reflection'
      "- REFLECTION (#{created_at.strftime('%b %d')}): \"#{metadata['prompt']}\""
    when 'discovery'
      "- DISCOVERY (#{created_at.strftime('%b %d')}): #{metadata['title']} | URL: #{metadata['url']}"
    end
  end

  # Extract domain from discovery URL (e.g., "youtube.com", "parents.com")
  def domain
    return nil unless discovery? && metadata['url'].present?

    begin
      uri = URI.parse(metadata['url'])
      host = uri.host&.downcase
      host&.gsub(/^www\./, '') # Remove www. prefix
    rescue URI::InvalidURIError
      nil
    end
  end

  # Class method to get recently used domains with counts
  def self.recent_domains(user_agent, days: 7)
    where(user_agent: user_agent, insight_type: :discovery)
      .where('created_at >= ?', days.days.ago)
      .map(&:domain)
      .compact
      .tally
      .sort_by { |_, count| -count }
  end

  # Class method to get recent reflection topics (goal IDs that were asked about)
  def self.recent_reflection_goal_ids(user_agent, days: 7)
    where(user_agent: user_agent, insight_type: :reflection)
      .where('created_at >= ?', days.days.ago)
      .flat_map { |r| r.goal_ids || [] }
      .tally
      .sort_by { |_, count| -count }
  end

  # Class method to get recent discovery goal coverage
  def self.recent_discovery_goal_ids(user_agent, days: 7)
    where(user_agent: user_agent, insight_type: :discovery)
      .where('created_at >= ?', days.days.ago)
      .flat_map { |d| d.goal_ids || [] }
      .tally
  end
end
