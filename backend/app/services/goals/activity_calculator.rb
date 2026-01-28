# frozen_string_literal: true

module Goals
  # Calculates goal activity level based on recent notes and messages.
  # Used by check-in system to determine appropriate check-in intervals.
  #
  # Activity levels:
  #   - :high     - 5+ activities in last 7 days (active engagement)
  #   - :moderate - 2-4 activities (steady progress)
  #   - :low      - 0-1 activities (quiet goal)
  #
  # Usage:
  #   calculator = Goals::ActivityCalculator.new(goal)
  #   result = calculator.calculate
  #   # => { level: :high, score: 7.5, details: { notes: 4, messages: 2, window_days: 7 } }
  #
  class ActivityCalculator
    def initialize(goal)
      @goal = goal
    end

    # Calculate activity level for the goal
    # @return [Hash] { level: Symbol, score: Float, details: Hash }
    def calculate
      notes = recent_notes_count
      messages = recent_messages_count

      # Notes weighted 1.5x (user took deliberate action to record)
      score = (notes * 1.5) + messages

      level = determine_level(score)

      {
        level: level,
        score: score.round(1),
        details: {
          notes: notes,
          messages: messages,
          window_days: Agents::Constants::ACTIVITY_WINDOW_DAYS
        }
      }
    end

    # Convenience method to get just the level
    # @return [Symbol] :high, :moderate, or :low
    def level
      calculate[:level]
    end

    private

    def recent_notes_count
      window = Agents::Constants::ACTIVITY_WINDOW_DAYS.days.ago

      Note.where(goal: @goal)
          .where(source: [:user, :import])
          .where('created_at > ?', window)
          .count
    end

    def recent_messages_count
      window = Agents::Constants::ACTIVITY_WINDOW_DAYS.days.ago

      ThreadMessage.where(agentable: @goal)
                   .where(source: :user)
                   .where('created_at > ?', window)
                   .count
    end

    def determine_level(score)
      high_threshold = Agents::Constants::ACTIVITY_HIGH_THRESHOLD
      moderate_threshold = Agents::Constants::ACTIVITY_MODERATE_THRESHOLD

      if score >= high_threshold
        :high
      elsif score >= moderate_threshold
        :moderate
      else
        :low
      end
    end
  end
end
