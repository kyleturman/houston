# frozen_string_literal: true

module Tools
  module System
    class GenerateFeedInsights < BaseTool
      # Tool metadata for planning and orchestration
      def self.metadata
        super.merge(
          name: 'generate_feed_insights',
          description: 'Record reflections and discoveries for the user feed based on cross-goal analysis. Use this after analyzing all goals to provide thoughtful questions and relevant resources.',
          params_hint: 'reflections (array of {prompt, goal_ids}), discoveries (array of {title, summary, url, goal_ids})'
        )
      end

      # JSON Schema for tool parameters
      def self.schema
        {
          type: 'object',
          properties: {
            reflections: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  prompt: { type: 'string' },
                  goal_ids: { type: 'array', items: { type: 'string' } }
                },
                required: ['prompt']
              }
            },
            discoveries: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  title: { type: 'string' },
                  summary: { type: 'string' },
                  url: { type: 'string' },
                  goal_ids: { type: 'array', items: { type: 'string' } }
                },
                required: ['title', 'url', 'summary']
              }
            }
          },
          required: ['reflections', 'discoveries'],
          additionalProperties: false
        }
      end

      # Params:
      # - reflections: Array of { prompt: String, goal_ids: Array }
      # - discoveries: Array of { title: String, summary: String, url: String, goal_ids: Array }
      # Returns: { success: true, reflection_count: Integer, discovery_count: Integer }
      def execute(reflections: [], discoveries: [])
        # Get UserAgent - supports both direct UserAgent execution and AgentTask belonging to UserAgent
        user_agent = resolve_user_agent
        unless user_agent
          return {
            success: false,
            error: 'This tool is only available to UserAgent or tasks belonging to UserAgent',
            observation: 'Error: This tool can only be used in UserAgent context.'
          }
        end

        # Get the current feed period from context first (passed through orchestrator),
        # then fallback to the feed_period accessor, then default_period based on current hour.
        # Using context avoids race conditions when multiple periods are triggered close together.
        # Only accept valid period values from Feeds::InsightScheduler::PERIODS.
        candidate_period = @context&.dig('feed_period') ||
                           @context&.dig('time_of_day') ||
                           user_agent.feed_period

        current_period = Feeds::InsightScheduler::PERIODS.include?(candidate_period) ? candidate_period : default_period

        # Handle case where LLM passes JSON strings instead of arrays
        reflections = parse_json_if_string(reflections)
        discoveries = parse_json_if_string(discoveries)

        reflections = Array(reflections)
        discoveries = Array(discoveries)

        # Emit progress update
        emit_tool_progress("Recording #{reflections.count} reflections and #{discoveries.count} discoveries...")

        created_count = 0

        total_insights = reflections.count + discoveries.count

        # Create FeedInsight records for reflections
        reflections.each_with_index do |reflection, index|
          next unless reflection.is_a?(Hash) && reflection['prompt'].present?

          begin
            # Parse goal_ids from string or array
            goal_ids = parse_goal_ids(reflection['goal_ids'])

            FeedInsight.create!(
              user: @user,
              user_agent: user_agent,
              insight_type: :reflection,
              goal_ids: goal_ids,
              display_order: calculate_display_order(index, total_insights),
              time_period: current_period,
              metadata: {
                'prompt' => normalize_text_spacing(reflection['prompt']),
                'insight_type' => reflection['insight_type']
              }
            )
            created_count += 1
          rescue => e
            Rails.logger.error("[GenerateFeedInsights] Failed to create reflection: #{e.message}")
          end
        end

        # Create FeedInsight records for discoveries
        discoveries.each_with_index do |discovery, index|
          next unless discovery.is_a?(Hash) && discovery['title'].present? && discovery['url'].present?

          begin
            # Parse goal_ids from string or array
            goal_ids = parse_goal_ids(discovery['goal_ids'])

            # Offset index for discoveries (they come after reflections)
            insight_index = reflections.count + index

            # Fetch OG image from URL (lightweight HTTP fetch)
            og_image = fetch_og_image(discovery['url'])

            FeedInsight.create!(
              user: @user,
              user_agent: user_agent,
              insight_type: :discovery,
              goal_ids: goal_ids,
              display_order: calculate_display_order(insight_index, total_insights),
              time_period: current_period,
              metadata: {
                'title' => normalize_text_spacing(discovery['title']),
                'summary' => normalize_text_spacing(discovery['summary']),
                'url' => discovery['url'],
                'source' => discovery['source'],
                'og_image' => og_image,
                'discovery_type' => discovery['discovery_type']
              }
            )
            created_count += 1
          rescue => e
            Rails.logger.error("[GenerateFeedInsights] Failed to create discovery: #{e.message}")
          end
        end

        # Publish SSE event so app knows to refresh feed
        publish_feed_ready_event(insight_count: created_count)

        # Emit completion update
        emit_tool_completion(
          "Recorded #{reflections.count} reflections and #{discoveries.count} discoveries",
          data: {
            reflection_count: reflections.count,
            discovery_count: discoveries.count
          }
        )

        {
          success: true,
          reflection_count: reflections.count,
          discovery_count: discoveries.count,
          observation: "Created #{created_count} feed insights (#{reflections.count} reflections, #{discoveries.count} discoveries) for today's feed."
        }
      end
      
      private

      # Parse JSON string to array if needed (LLM sometimes returns JSON strings)
      def parse_json_if_string(value)
        return value unless value.is_a?(String)

        begin
          parsed = JSON.parse(value)
          Rails.logger.info("[GenerateFeedInsights] Parsed JSON string parameter: #{parsed.class}")
          parsed
        rescue JSON::ParserError => e
          Rails.logger.warn("[GenerateFeedInsights] Failed to parse JSON string: #{e.message}")
          value
        end
      end

      # Parse goal_ids from various formats (string, array of strings, array of integers)
      def parse_goal_ids(value)
        return [] if value.nil? || value.empty?

        # Convert to array if single value
        ids = Array(value)

        # Convert to integers, filtering out invalid values
        ids.map do |id|
          case id
          when Integer
            id if id > 0  # Exclude 0 and negative IDs
          when String
            parsed = id.to_i
            parsed if parsed > 0  # Exclude 0 (empty string converts to 0) and negative IDs
          else
            nil
          end
        end.compact
      end

      # Calculate display_order for weighted-random feed sorting
      # Insights created together get slightly different orders for variety
      def calculate_display_order(index, total)
        now = Time.current
        day_start = now.beginning_of_day
        minutes_since_midnight = ((now - day_start).to_i / 60)

        # Spread insights created together slightly apart (10 units per position)
        # This prevents all insights from having identical ordering
        spread = (index - total / 2) * 10

        # Add randomization (+/- 120 minutes) for feed variety
        randomization = rand(-120..120)

        minutes_since_midnight + spread + randomization
      end

      # Fetch OG image from URL using lightweight HTTP request
      def fetch_og_image(url)
        Web::OgMetadataFetcher.fetch_og_image(url)
      rescue => e
        Rails.logger.warn("[GenerateFeedInsights] Failed to fetch OG image for #{url}: #{e.message}")
        nil
      end

      # Default period based on current hour (fallback if not set by job)
      def default_period
        hour = Time.current.hour
        if hour < 12
          'morning'
        elsif hour < 17
          'afternoon'
        else
          'evening'
        end
      end

      # Normalize text spacing to fix common LLM output issues
      # Fixes patterns like "before2026" -> "before 2026" and "40Most" -> "40 Most"
      def normalize_text_spacing(text)
        return text unless text.is_a?(String)

        text
          .gsub(/([a-z])(\d)/, '\1 \2')  # lowercase followed by digit: "before2026" -> "before 2026"
          .gsub(/(\d)([A-Z])/, '\1 \2')  # digit followed by uppercase: "40Most" -> "40 Most"
      end

      # Publish SSE event that feed insights are ready (so app can refresh feed)
      def publish_feed_ready_event(insight_count:)
        global_channel = Streams::Channels.global_for_user(user: @user)
        Streams::Broker.publish(
          global_channel,
          event: 'feed_insights_ready',
          data: {
            insight_count: insight_count,
            generated_at: Time.current.iso8601
          }
        )
        Rails.logger.info("[GenerateFeedInsights] Published feed_insights_ready: #{insight_count} insights")
      rescue => e
        Rails.logger.error("[GenerateFeedInsights] Failed to publish SSE event: #{e.message}")
        # Don't fail the operation if SSE publish fails
      end

      # Resolve UserAgent from agentable context
      # Supports both direct UserAgent execution and AgentTask belonging to UserAgent
      def resolve_user_agent
        if @agentable.is_a?(UserAgent)
          @agentable
        elsif @agentable.is_a?(AgentTask) && @agentable.taskable_type == 'UserAgent'
          @agentable.taskable
        else
          nil
        end
      end
    end
  end
end
