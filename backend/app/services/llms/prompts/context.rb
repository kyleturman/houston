# frozen_string_literal: true

require 'cgi'

module Llms
  module Prompts
    # ========================================================================
    # XML ESCAPING HELPER
    # ========================================================================
    # Sanitizes user-controlled strings before embedding in XML prompts.
    # Prevents prompt injection by escaping XML special characters.
    #
    # Usage: XmlSafe.xml_safe(user_input)
    #
    module XmlSafe
      module_function

      # Escapes user input for safe embedding in XML prompts
      # Converts: & → &amp;  < → &lt;  > → &gt;  " → &quot;  ' → &#39;
      def xml_safe(value)
        CGI.escapeHTML(value.to_s)
      end
    end

    # Core context from data models to provide to prompts
    #
    # PUBLIC API (Core Context Builders):
    #   - time                   → Current date/time context
    #   - learnings              → User learnings/insights
    #   - notes                  → Notes with flexible scoping
    #   - agent_history          → Previous session summaries
    #
    # UTILITIES:
    #   - recent_tool_errors     → Error detection helper
    #
    module Context
      module_function

      # ======================================================================
      # CORE CONTEXT BUILDERS (Public API)
      # ======================================================================
      # These are the main methods used by prompt builders to compose
      # structured XML context for LLM calls

      # ----------------------------------------------------------------------
      # Time Context - Current date/time for temporal awareness
      # ----------------------------------------------------------------------
      # Pass user: to get timezone-aware context (recommended for all user-facing prompts)

      def time(user: nil)
        if user
          # Use user's timezone for accurate "today" context
          user_timezone = user.timezone_or_default
          now_in_tz = Time.current.in_time_zone(user_timezone)
          current_date = now_in_tz.to_date.iso8601
          current_time = now_in_tz.strftime('%I:%M %p')  # e.g., "02:30 PM"
          current_hour = now_in_tz.hour
          current_year = now_in_tz.year
          current_month = now_in_tz.strftime('%B')
          day_of_week = now_in_tz.strftime('%A')
          timezone = user_timezone
        elsif Time.respond_to?(:zone) && Time.zone
          current_date = Time.zone.today.iso8601
          current_time = Time.zone.now.strftime('%I:%M %p')
          current_hour = Time.zone.now.hour
          current_year = Time.zone.now.year
          current_month = Time.zone.now.strftime('%B')
          day_of_week = Time.zone.now.strftime('%A')
          timezone = Time.zone.now.zone
        else
          current_date = Time.now.strftime('%Y-%m-%d')
          current_time = Time.now.strftime('%I:%M %p')
          current_hour = Time.now.hour
          current_year = Time.now.year
          current_month = Time.now.strftime('%B')
          day_of_week = Time.now.strftime('%A')
          timezone = 'UTC'
        end

        <<~TIME
          <time_context>
            <current_date>#{current_date}</current_date>
            <current_time>#{current_time}</current_time>
            <current_hour>#{current_hour}</current_hour>
            <current_year>#{current_year}</current_year>
            <current_month>#{current_month}</current_month>
            <day_of_week>#{day_of_week}</day_of_week>
            <timezone>#{timezone}</timezone>
            <critical>When including years in search queries, ALWAYS use #{current_year} (the current year). NEVER use past years like #{current_year - 1}.</critical>
          </time_context>
        TIME
      end

      # ----------------------------------------------------------------------
      # Learnings Context - User insights and preferences
      # ----------------------------------------------------------------------

      def learnings(goal: nil, task: nil)
        # Get learnings from goal directly or via task
        learning_source = goal || task&.goal
        return "" unless learning_source
        return "" if learning_source.learnings.blank?
        
        learnings_xml = format_learnings_xml(learning_source.learnings)
        
        <<~LEARNINGS

          #{learnings_xml}
        LEARNINGS
      end

      # ----------------------------------------------------------------------
      # Notes Context - Flexible notes with scoping
      # ----------------------------------------------------------------------
      # Supports both goal-specific notes and unassigned user notes
      # 
      # Examples:
      #   notes(goal: goal)           # Goal notes (user + agent)
      #   notes(user: user)           # Unassigned user notes

      def notes(goal: nil, user: nil)
        return nil unless goal || user

        begin
          # Get data from Note model based on context
          data = if goal
            Note.context_for_goal(goal)
          elsif user
            Note.context_for_user_agent(user)
          end
          
          return nil unless data

          parts = []

          # User notes section (full content)
          if data[:user_notes].any?
            user_xml = format_notes_xml(data[:user_notes])
            
            if user && !goal
              # UserAgent context - unassigned notes
              return <<~NOTES
                <personal_notes>
                  <note>Personal notes not assigned to any specific goal:</note>
                #{user_xml}
                </personal_notes>
              NOTES
            else
              # Goal context - user notes
              parts << "  <user_notes>\n#{user_xml}\n  </user_notes>"
            end
          end

          # Agent notes section (only for goals, only recent)
          if goal && data[:agent_notes]&.any?
            agent_xml = format_notes_xml(data[:agent_notes])
            parts << "  <recent_research>\n#{agent_xml}\n  </recent_research>"
          end

          # Show titles of older research to avoid duplicate work
          older_titles = data[:older_research_titles] || []
          if older_titles.any?
            titles_list = older_titles.map { |t| "- #{XmlSafe.xml_safe(t.to_s)}" }.join("\n")
            parts << "  <previous_research>\n  Topics already researched (use search_notes for details, don't duplicate):\n#{titles_list}\n  </previous_research>"
          end

          return nil if parts.empty?

          <<~NOTES
            <notes_context>
            #{parts.join("\n\n")}
            </notes_context>
          NOTES
        rescue => e
          Rails.logger.debug("[Llms::Prompts::Context] notes failed #{e.class}: #{e.message}")
          nil
        end
      end

      # ======================================================================
      # UTILITIES
      # ======================================================================
      # Helper methods for specialized use cases

      # ----------------------------------------------------------------------
      # Error Detection - Counts recent tool errors in LLM history
      # ----------------------------------------------------------------------

      def recent_tool_errors(agentable)
        history = agentable.get_llm_history
        return 0 if history.length < 5
        
        # Check last 10 entries for tool error patterns
        recent_entries = history.last(10)
        error_count = 0
        
        recent_entries.each do |entry|
          if entry["role"] == "user" && entry["content"].is_a?(Array)
            entry["content"].each do |item|
              if item.is_a?(Hash) && item["type"] == "tool_result"
                content = item["content"].to_s.downcase
                # Count various error patterns
                if content.include?("error") || 
                   content.include?("unknown keyword") || 
                   content.include?("missing keyword") ||
                   content.include?("failed")
                  error_count += 1
                end
              end
            end
          end
        end
        
        error_count
      end

      # ----------------------------------------------------------------------
      # Available Integrations - MCP servers the goal has access to
      # ----------------------------------------------------------------------

      def available_integrations(goal:)
        return "" unless goal&.enabled_mcp_servers.present?

        # Get server info dynamically from McpServer records
        servers = McpServer.where(name: goal.enabled_mcp_servers)

        integrations = servers.filter_map do |server|
          next if server.description.blank?
          "  - #{XmlSafe.xml_safe(server.display_name)}: #{XmlSafe.xml_safe(server.description)}"
        end

        return "" if integrations.empty?

        <<~INTEGRATIONS

          <available_integrations>
          Your tasks have access to these connected services:
          #{integrations.join("\n")}

          When users ask about these services, create tasks that use them.
          </available_integrations>
        INTEGRATIONS
      end

      # ----------------------------------------------------------------------
      # Agent History - Previous session summaries for context
      # ----------------------------------------------------------------------

      def agent_history(agentable:)
        # UserAgent has fewer history entries since most sessions are autonomous
        # and we filter those out. Goal agents have more conversational history.
        limit = agentable.user_agent? ? 3 : Agents::Constants::AGENT_HISTORY_SUMMARY_COUNT

        summaries = agentable.recent_agent_history_summaries(limit: limit)

        return "" if summaries.empty?

        <<~XML
          <your_memory>
          What you remember from recent conversations with this user:

          #{summaries.join("\n\n")}

          Use search_agent_history if you need to recall specific details.
          </your_memory>
        XML
      end

      # ----------------------------------------------------------------------
      # Scheduled Check-Ins - Show upcoming autonomous executions
      # ----------------------------------------------------------------------

      def scheduled_check_ins(goal:)
        return "" unless goal&.goal?

        parts = []

        # Show recurring schedule if set
        if goal.has_check_in_schedule?
          schedule = goal.check_in_schedule
          freq_text = case schedule['frequency']
          when 'daily' then "daily at #{schedule['time']}"
          when 'weekdays' then "weekdays at #{schedule['time']}"
          when 'weekly' then "#{schedule['day_of_week']}s at #{schedule['time']}"
          else schedule['frequency']
          end
          parts << "  <recurring_schedule frequency=\"#{freq_text}\">#{schedule['intent']}</recurring_schedule>"

          # Show next scheduled occurrence
          if (scheduled = goal.scheduled_check_in)
            time_text = time_until(Time.parse(scheduled['scheduled_for']))
            parts << "  <next_scheduled in=\"#{time_text}\">#{scheduled['intent']}</next_scheduled>"
          end
        end

        # Show follow-up if set
        if (follow_up = goal.next_follow_up)
          time_text = time_until(Time.parse(follow_up['scheduled_for']))
          parts << "  <follow_up scheduled_in=\"#{time_text}\">#{follow_up['intent']}</follow_up>"
        end

        return "" if parts.empty?

        <<~CHECK_INS

          <your_check_ins>
          #{parts.join("\n")}
          </your_check_ins>
        CHECK_INS
      end

      # Format time until a future timestamp
      def time_until(time)
        hours_away = ((time - Time.current) / 1.hour).round
        if hours_away < 24
          "#{hours_away} hours"
        elsif hours_away < 168  # 7 days
          "#{(hours_away / 24.0).round} days"
        else
          "#{(hours_away / 168.0).round} weeks"
        end
      end

      # ----------------------------------------------------------------------
      # Recent Task Outcomes - What tasks accomplished for this goal
      # ----------------------------------------------------------------------

      def recent_task_outcomes(goal:)
        return "" unless goal&.goal?

        # Get recently completed tasks for this goal (last 7 days)
        recent_tasks = AgentTask.where(goal: goal)
                                .where(status: :completed)
                                .where('updated_at > ?', 7.days.ago)
                                .order(updated_at: :desc)
                                .limit(5)

        return "" if recent_tasks.empty?

        parts = recent_tasks.map do |task|
          time_ago = time_ago_in_words(task.updated_at)
          summary = task.result_summary.presence || "Completed"

          "  <task completed=\"#{time_ago}\">\n" \
          "    <title>#{XmlSafe.xml_safe(task.title)}</title>\n" \
          "    <outcome>#{XmlSafe.xml_safe(summary)}</outcome>\n" \
          "  </task>"
        end

        <<~TASKS

          <recent_task_outcomes note="What your tasks have accomplished recently">
          #{parts.join("\n")}
          </recent_task_outcomes>
        TASKS
      end

      # Format time ago in words
      def time_ago_in_words(time)
        seconds = Time.current - time
        if seconds < 60
          "just now"
        elsif seconds < 3600
          "#{(seconds / 60).round} minutes ago"
        elsif seconds < 86400
          "#{(seconds / 3600).round} hours ago"
        else
          "#{(seconds / 86400).round} days ago"
        end
      end

      # ======================================================================
      # PRIVATE HELPER METHODS
      # ======================================================================
      # XML formatting helpers - keep these DRY

      # Format learnings array as XML
      def format_learnings_xml(learnings)
        return "" if learnings.blank?

        xml = "<learnings>\n"
        learnings.each do |learning|
          xml += "  <learning id=\"#{learning['id'] || learning[:id]}\" "
          xml += "timestamp=\"#{learning['created_at'] || learning[:created_at]}\">\n"
          xml += "    #{XmlSafe.xml_safe((learning['content'] || learning[:content]).to_s)}\n"
          xml += "  </learning>\n"
        end
        xml += "</learnings>"
        xml
      end

      # Format notes array as XML
      def format_notes_xml(notes)
        notes.map do |note|
          date = note[:created_at].strftime('%Y-%m-%d')
          source_attr = note[:source] ? " source=\"#{XmlSafe.xml_safe(note[:source].to_s)}\"" : ""

          xml = "    <note date=\"#{date}\"#{source_attr}>\n"
          xml += "      <title>#{XmlSafe.xml_safe(note[:title].to_s)}</title>\n"

          # Handle URL notes with web_summary
          if note[:metadata] && note[:metadata]['web_summary'].present?
            # Note has both user commentary and web summary
            source_url = note[:metadata]['source_url']

            if note[:content].present?
              # User provided commentary along with the link
              xml += "      <user_note>#{XmlSafe.xml_safe(note[:content].to_s)}</user_note>\n"
            end

            xml += "      <link_summary>#{XmlSafe.xml_safe(note[:metadata]['web_summary'].to_s)}</link_summary>\n"
            xml += "      <source_url>#{XmlSafe.xml_safe(source_url.to_s)}</source_url>\n" if source_url.present?
          elsif note[:metadata] && note[:metadata]['source_url'].present?
            # URL note but processing not completed yet - use SEO description as fallback
            seo_description = note[:metadata]['seo']&.dig('description')
            source_url = note[:metadata]['source_url']

            if note[:content].present?
              xml += "      <user_note>#{XmlSafe.xml_safe(note[:content].to_s)}</user_note>\n"
            end

            if seo_description.present?
              xml += "      <seo_description>#{XmlSafe.xml_safe(seo_description.to_s)}</seo_description>\n"
            end

            xml += "      <source_url>#{XmlSafe.xml_safe(source_url.to_s)}</source_url>\n"
          else
            # Regular note (no URL)
            xml += "      <content>#{XmlSafe.xml_safe(note[:content].to_s)}</content>\n"
          end

          xml += "    </note>"
          xml
        end.join("\n")
      end

    end
  end
end
