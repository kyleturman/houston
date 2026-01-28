# frozen_string_literal: true

class Note < ApplicationRecord
  belongs_to :user
  belongs_to :goal, optional: true

  enum :source, { user: 0, agent: 1, import: 2, system: 3, app_intent: 4 }

  # Constants for context building
  USER_NOTES_LIMIT = 50
  AGENT_NOTES_LIMIT = 10
  AGENT_NOTES_RECENCY_DAYS = 7  # Only include agent notes from last week
  TRUNCATE_LENGTH = 150
  FULL_CONTENT_THRESHOLD = 500
  SEARCH_TOOL_THRESHOLD = 70

  # Scopes
  scope :user_created, -> { where(source: [:user, :import, :system, :app_intent]) }
  scope :agent_created, -> { where(source: :agent) }
  scope :unassigned, -> { where(goal_id: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Encrypt sensitive fields so they cannot be read from disk directly
  encrypts :title
  encrypts :content
  # Cast metadata as JSON and encrypt it
  attribute :metadata, :json, default: {}
  encrypts :metadata

  validates :content, presence: true, unless: -> { metadata['source_url'].present? }
  validates :source, presence: true
  validate :goal_belongs_to_user

  # Set display_order for agent notes (used for weighted-random feed sorting)
  before_create :set_display_order_for_agent_notes

  private

  # Ensure the note's goal is owned by the same user
  def goal_belongs_to_user
    return if goal.nil? || user.nil?
    errors.add(:goal, 'must belong to the same user') if goal.user_id != user_id
  end

  # Calculate display_order for agent notes (weighted random for feed variety)
  # Only agent notes get display_order (user notes don't appear in feed)
  def set_display_order_for_agent_notes
    return unless source == 'agent'

    # Base order: minutes since midnight
    timestamp = created_at || Time.current
    day_start = timestamp.beginning_of_day
    minutes_since_midnight = ((timestamp - day_start).to_i / 60)

    # Add randomization (+/- 120 minutes worth of ordering) for variety
    # This creates weighted-random sorting: recent items tend higher, but with variety
    randomization = rand(-120..120)

    self.display_order = minutes_since_midnight + randomization
  end

  # ========================================================================
  # CONTEXT BUILDING - Returns formatted data ready for prompt composition
  # ========================================================================

  # Returns formatted hash ready for prompt composition
  # User notes: all recent (these are what the user cares about)
  # Agent notes: only last 7 days (older research is searchable but not in context)
  # Older topics: titles of older agent notes to avoid duplicate research
  def self.context_for_goal(goal)
    return nil unless goal

    user_notes = user_created.where(goal: goal).recent.limit(USER_NOTES_LIMIT).to_a

    # Agent notes limited by recency - older research can be found via search_notes
    recent_cutoff = AGENT_NOTES_RECENCY_DAYS.days.ago
    agent_notes = agent_created
      .where(goal: goal)
      .where('created_at > ?', recent_cutoff)
      .recent
      .limit(AGENT_NOTES_LIMIT)
      .to_a

    # Get titles of older agent notes (to avoid duplicate research)
    older_agent_titles = agent_created
      .where(goal: goal)
      .where('created_at <= ?', recent_cutoff)
      .order(created_at: :desc)
      .limit(30)
      .pluck(:title)
      .compact
      .reject(&:blank?)

    return nil if user_notes.empty? && agent_notes.empty? && older_agent_titles.empty?

    {
      user_notes: user_notes.map { |n| n.to_context_hash(full: true) },
      agent_notes: agent_notes.map { |n| n.to_context_hash(full: false) },
      total_count: goal.notes.count,
      shown_count: user_notes.count + agent_notes.count,
      older_research_titles: older_agent_titles  # Titles only - to avoid duplicate research
    }
  end
  
  # Returns formatted hash for UserAgent context (unassigned notes only)
  def self.context_for_user_agent(user)
    return nil unless user

    notes = user_created.where(user: user).unassigned.recent.limit(USER_NOTES_LIMIT).to_a
    return nil if notes.empty?

    {
      user_notes: notes.map { |n| n.to_context_hash(full: true) },
      total_count: notes.count,
      shown_count: notes.count
    }
  end

  public  # Make context methods public so class methods can call them

  # Instance method for formatting - returns hash ready for XML composition
  def to_context_hash(full: true)
    {
      title: title,
      content: formatted_content(full: full),
      source: source,
      created_at: created_at,
      metadata: metadata
    }
  end

  private

  # Format content with truncation strategy
  def formatted_content(full: true)
    if full && content.to_s.length <= FULL_CONTENT_THRESHOLD
      content
    else
      content.to_s.truncate(TRUNCATE_LENGTH)
    end
  end

  # ========================================================================
  # SEARCH FUNCTIONALITY
  # ========================================================================

  public

  # Class helpers
  class << self
    # Search notes for a goal by query string
    # Returns notes ordered by relevance (most recent first for now)
    def search_for_goal(goal:, query:, limit: 8)
      return [] if goal.nil? || query.blank?

      # Get all notes for this goal (already scoped, so dataset is small)
      candidates = where(goal: goal).order(created_at: :desc)

      # Normalize query for matching
      query_terms = query.to_s.downcase.split(/\s+/).reject(&:blank?)
      return [] if query_terms.empty?

      # Score and filter notes by query match
      scored_notes = candidates.filter_map do |note|
        score = calculate_relevance_score(note, query_terms)
        next if score.zero?
        { note: note, score: score }
      end

      # Sort by score (highest first), then take top N
      scored_notes.sort_by { |sn| -sn[:score] }
                  .take(limit)
                  .map { |sn| sn[:note] }
    end

    private

    # Calculate relevance score for a note given query terms
    # Higher score = more relevant
    def calculate_relevance_score(note, query_terms)
      score = 0

      # Decrypt fields for searching
      title_text = note.title.to_s.downcase
      content_text = note.content.to_s.downcase

      query_terms.each do |term|
        # Title matches are worth more
        score += 3 if title_text.include?(term)
        # Content matches
        score += 1 if content_text.include?(term)
      end

      score
    end

  end
end

