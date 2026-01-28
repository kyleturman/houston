# frozen_string_literal: true

module Api
  # Ultra-simple feed API
  # Feed = today's agent notes + today's insights
  # No "generation" concept - feed is just a filtered query
  class FeedController < BaseController
    # GET /api/feed/current - Returns today's feed
    def current
      render json: {
        items: feed_items,
        date: Time.current.beginning_of_day.iso8601
      }
    end

    # GET /api/feed/history?date=YYYY-MM-DD - Returns historical feed
    def history
      date = params[:date] ? Date.parse(params[:date]) : Date.current

      items = feed_items_for_date(date)

      render json: {
        date: date.beginning_of_day.to_time.iso8601,
        items: items.map { |item| format_feed_item(item) }
      }
    rescue ArgumentError
      render json: { error: 'Invalid date format' }, status: :bad_request
    end

    # GET /api/feed/schedule - Returns feed schedule with per-period settings
    def schedule
      return render json: { error: 'User agent not found' }, status: :not_found unless current_user.user_agent

      scheduler = Feeds::InsightScheduler.new(current_user.user_agent)
      jobs = current_user.user_agent.feed_schedule&.dig('jobs') || {}

      # Build per-period response
      periods = Feeds::InsightScheduler::PERIODS.to_h do |period|
        job_data = jobs[period]
        next_run = job_data&.dig('scheduled_for')

        [period, {
          enabled: scheduler.period_enabled?(period),
          time: scheduler.period_time(period),
          next_run: next_run
        }]
      end

      render json: {
        periods: periods,
        timezone: current_user.timezone_or_default
      }
    end

    # PATCH /api/feed/schedule - Update a period's settings
    def update_schedule
      return render json: { error: 'User agent not found' }, status: :not_found unless current_user.user_agent

      period = params[:period]
      time = params[:time]
      enabled = params[:enabled]

      unless Feeds::InsightScheduler::PERIODS.include?(period)
        return render json: { error: "Invalid period: #{period}" }, status: :bad_request
      end

      scheduler = Feeds::InsightScheduler.new(current_user.user_agent)

      begin
        scheduler.update_period!(period, time: time, enabled: enabled)

        # Return updated schedule
        jobs = current_user.user_agent.reload.feed_schedule&.dig('jobs') || {}
        periods = Feeds::InsightScheduler::PERIODS.to_h do |p|
          job_data = jobs[p]
          [p, {
            enabled: scheduler.period_enabled?(p),
            time: scheduler.period_time(p),
            next_run: job_data&.dig('scheduled_for')
          }]
        end

        render json: {
          periods: periods,
          timezone: current_user.timezone_or_default
        }
      rescue ArgumentError => e
        render json: { error: e.message }, status: :bad_request
      end
    end

    # POST /api/feed/generate_insights - TEMP: Manually trigger feed insight generation
    def generate_insights
      return render json: { error: 'User agent not found' }, status: :not_found unless current_user.user_agent

      # Trigger UserAgent to generate feed insights
      Agents::Orchestrator.perform_async(
        'UserAgent',
        current_user.user_agent.id,
        { 'type' => 'feed_generation', 'time_of_day' => 'manual', 'scheduled' => false }
      )

      render json: { success: true, message: 'Feed insight generation triggered' }
    end

    private

    # Today's feed items (notes + insights) sorted by display_order
    def feed_items
      notes = todays_notes
      insights = todays_insights

      # Combine and sort by display_order (weighted random), then created_at
      combined = (notes.to_a + insights.to_a)
        .sort_by { |item| [-(item.display_order || 0), -item.created_at.to_i] }

      combined.map { |item| format_feed_item(item) }
    end

    # Today's agent notes only (user notes don't appear in feed)
    # Uses user's timezone to determine "today"
    def todays_notes
      user_timezone = current_user.timezone_or_default
      beginning_of_user_day = Time.current.in_time_zone(user_timezone).beginning_of_day

      current_user.notes
        .where(source: :agent)
        .where('created_at >= ?', beginning_of_user_day)
    end

    # Today's insights (reflections + discoveries)
    # Uses user's timezone to determine "today"
    def todays_insights
      return [] unless current_user.user_agent

      user_timezone = current_user.timezone_or_default
      beginning_of_user_day = Time.current.in_time_zone(user_timezone).beginning_of_day

      current_user.user_agent.feed_insights
        .where('created_at >= ?', beginning_of_user_day)
    end

    # Feed items for a specific date
    def feed_items_for_date(date)
      notes = current_user.notes
        .where(source: :agent)
        .where(created_at: date.all_day)

      insights = current_user.user_agent&.feed_insights
        &.where(created_at: date.all_day) || []

      # Sort by display_order (weighted random)
      combined = (notes.to_a + insights.to_a)
        .sort_by { |item| [-(item.display_order || 0), -item.created_at.to_i] }

      combined
    end

    # Format item for JSON response
    def format_feed_item(item)
      case item
      when Note
        # Convert to user's timezone before extracting hour for time period calculation
        user_timezone = current_user.timezone_or_default
        local_time = item.created_at.in_time_zone(user_timezone)
        {
          id: item.id.to_s,
          type: 'note',
          content: {
            id: item.id.to_s,
            title: item.title,
            content: item.content,
            goal_id: item.goal_id&.to_s,
            goal_name: item.goal&.title,
            created_at: item.created_at.iso8601,
            time_period: time_period_for_hour(local_time.hour)
          }
        }
      when FeedInsight
        {
          id: item.id.to_s,
          type: item.insight_type,  # 'reflection' or 'discovery'
          content: format_insight_content(item)
        }
      end
    end

    # Format FeedInsight content based on type
    def format_insight_content(insight)
      case insight.insight_type
      when 'reflection'
        {
          prompt: insight.metadata['prompt'],
          goal_ids: insight.goal_ids.map(&:to_s),
          insight_type: insight.metadata['insight_type'],
          created_at: insight.created_at.iso8601,
          time_period: insight.time_period
        }
      when 'discovery'
        {
          title: insight.metadata['title'],
          summary: insight.metadata['summary'],
          url: insight.metadata['url'],
          source: insight.metadata['source'],
          og_image: insight.metadata['og_image'],
          goal_ids: insight.goal_ids.map(&:to_s),
          discovery_type: insight.metadata['discovery_type'],
          created_at: insight.created_at.iso8601,
          time_period: insight.time_period
        }
      end
    end

    # Determine time period from hour of day using user's schedule boundaries
    # morning: 12am to afternoon_start
    # afternoon: afternoon_start to evening_start
    # evening: evening_start to 12am
    def time_period_for_hour(hour)
      afternoon_start = schedule_hour_for('afternoon')
      evening_start = schedule_hour_for('evening')

      if hour < afternoon_start
        'morning'
      elsif hour < evening_start
        'afternoon'
      else
        'evening'
      end
    end

    # Get the hour for a schedule period (e.g., 12 for "12:00")
    def schedule_hour_for(period)
      return default_hour_for(period) unless current_user.user_agent

      scheduler = Feeds::InsightScheduler.new(current_user.user_agent)
      time_str = scheduler.period_time(period)
      time_str.split(':').first.to_i
    end

    # Default hours if no user_agent exists
    def default_hour_for(period)
      case period
      when 'afternoon' then 12
      when 'evening' then 17
      else 6
      end
    end
  end
end
