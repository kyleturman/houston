# frozen_string_literal: true

require 'cgi'

module Llms
  module Prompts
    module UserAgent
      module_function

      # Escape user input for safe embedding in XML prompts
      # Matches XmlSafe.xml_safe from context.rb
      def xml_safe(value)
        CGI.escapeHTML(value.to_s)
      end

      # ========================================================================
      # USER AGENT-SPECIFIC CONTEXT BUILDERS
      # ========================================================================

      # Build user agent context (active goals with learnings + recent notes + UA learnings)
      # Goal learnings are the agent's memory - always accessible, not just for feed generation
      def user_agent_context(user:)
        parts = []

        # Active goals with their learnings and recent notes (agent's memory)
        active_goals = user.goals.where.not(status: :archived).order(:created_at)
        if active_goals.any?
          goals_xml = active_goals.map do |goal|
            goal_parts = ["  <goal id=\"#{goal.id}\">"]
            goal_parts << "    <title>#{xml_safe(goal.title)}</title>"
            goal_parts << "    <description>#{xml_safe(goal.description)}</description>" if goal.description.present?

            # Include goal learnings - durable facts about this goal
            if goal.learnings.any?
              learnings = goal.learnings.first(5).map { |l| "      <learning>#{xml_safe(l['content'])}</learning>" }.join("\n")
              goal_parts << "    <learnings>\n#{learnings}\n    </learnings>"
            end

            # Include recent notes - what's been researched/saved recently
            recent_notes = goal.notes.order(created_at: :desc).limit(4)
            if recent_notes.any?
              notes = recent_notes.map do |n|
                title = n.title.present? ? n.title.truncate(60) : "(saved link)"
                source = n.source == "user" ? "user" : "agent"
                "      <note source=\"#{source}\">#{xml_safe(title)}</note>"
              end.join("\n")
              goal_parts << "    <recent_notes>\n#{notes}\n    </recent_notes>"
            end

            goal_parts << "  </goal>"
            goal_parts.join("\n")
          end.join("\n")

          parts << "<goals note=\"Your memory about each goal\">\n#{goals_xml}\n</goals>"
        end

        # UserAgent-level learnings (cross-goal preferences)
        if user.user_agent.present? && user.user_agent.learnings.present?
          learnings_xml = Context.send(:format_learnings_xml, user.user_agent.learnings)
          parts << "<user_preferences note=\"Cross-goal preferences\">\n#{learnings_xml}\n</user_preferences>"
        end

        parts.join("\n\n")
      end

      # Build goals context for feed generation
      def goals_feed_context(goals:)
        goals.map { |g|
          context = "#{xml_safe(g.title)}"
          context += " - #{xml_safe(g.description)}" if g.description.present?

          if g.learnings.any?
            context += "\n  What you've learned: #{g.learnings.map { |l| xml_safe(l['content']) }.join('; ')}"
          end

          context
        }.join("\n\n")
      end

      # ========================================================================
      # USER AGENT SYSTEM PROMPT
      # ========================================================================

      def system_prompt(user:, user_agent:, notes_text: nil)
        # Build dynamic context (changes per user)
        time_ctx = Context.time(user: user)
        user_ctx = user_agent_context(user: user)
        history_ctx = Context.agent_history(agentable: user_agent)

        <<~PROMPT
          #{Core.system_prompt}

          <role_instructions>
          <primary_role>Cross-Goal Orchestrator</primary_role>
          <personality>A warm, encouraging friend who sees the user's full picture across all goals.</personality>

          <core_responsibilities>
          <responsibility priority="high">Respond to user messages - Answer questions using your knowledge of their goals and learnings</responsibility>
          <responsibility>Learn user patterns, preferences, and rhythms</responsibility>
          <responsibility>Celebrate progress and notice connections between goals</responsibility>
          <responsibility>Identify opportunities for synergy and coordination</responsibility>
          <responsibility>Generate personalized home feed insights</responsibility>
          <responsibility>Decide: alerts (urgent) vs feed items (timely)</responsibility>
          </core_responsibilities>

          <when_responding_to_messages>
          <guideline>Use the `send_message` tool to reply</guideline>
          <guideline>Reference their learnings and goal context</guideline>
          <guideline>Be warm, personal, and helpful</guideline>
          <guideline>Keep responses concise and friendly</guideline>
          </when_responding_to_messages>

          <tone_and_style>
          Supportive and proactive - notice small wins, understand context, show the bigger picture.
          Like a trusted friend who remembers everything and genuinely cares.
          </tone_and_style>

          <examples>
          <example>Great momentum this week! You've made progress on both Spanish learning and the garden project.</example>
          <example>I noticed you're researching budgeting and meal planning - these could work well together.</example>
          <example>It's been quiet on the fitness goal lately. Want to revisit it, or should we focus elsewhere?</example>
          </examples>

          <feed_generation>
          When you receive a <feed_generation_task> with goal priorities and recent content:
          - Create a task to research and generate feed insights
          - The task will search for discoveries, write reflections, and call generate_feed_insights
          - Keep task title concise (e.g., "Dec 15, morning insights")
          - Include goal priorities and freshness context in task instructions
          - Do NOT try to use generate_feed_insights yourself - that tool only works for tasks

          <task_instructions_template>
          Include in task instructions:
          1. Goal priorities (which goals need attention)
          2. Recent content to avoid (for freshness)
          3. User preferences from learnings (source preferences, interests)
          4. Target: 1 reflection + 4-6 discoveries
          </task_instructions_template>
          </feed_generation>
          </role_instructions>

          #{time_ctx}
          #{history_ctx}
          #{user_ctx}
          #{notes_text}
        PROMPT
      end

      # ========================================================================
      # USER AGENT FEED GENERATION
      # ========================================================================

      def feed_generation_prompt(user:, goals:, recent_insights:, time_of_day: 'morning')
        user_agent = user.user_agent

        # Format task title: "Dec 24, morning insights"
        user_time = Time.current.in_time_zone(user.timezone_or_default)
        date_str = user_time.strftime('%b %-d')
        task_title = "#{date_str}, #{time_of_day} insights"

        # Build context for task instructions
        priority_xml = build_goal_priorities_xml(goals: goals, user_agent: user_agent)
        recent_content_xml = build_recent_coverage_xml(user_agent: user_agent, recent_insights: recent_insights)
        preferences_xml = build_user_preferences_xml(user_agent: user_agent)

        # Build goals summary for task context
        goals_summary = goals.map { |g| "- #{xml_safe(g.title)} (id: #{g.id})" }.join("\n")

        <<~PROMPT
          <feed_generation_task>
          Create a task titled "#{task_title}" to generate today's feed insights.

          Use create_task with these instructions for the task agent:

          <task_instructions>
          Generate #{time_of_day} feed insights: 1 reflection and 4-6 discoveries.

          GOALS TO COVER:
          #{goals_summary}

          #{priority_xml}

          #{recent_content_xml}

          #{preferences_xml.present? ? preferences_xml : ""}

          WORKFLOW:
          1. Search community/creator sources first (Reddit, HN, Substack, niche forums) for high-priority goals
          2. Use brave_news_search for timely content; use general search sparingly
          3. Write 1 reflection prompt (see REFLECTION GUIDELINES below)
          4. Call generate_feed_insights with valid JSON arrays for reflections and discoveries
             - Keep text simple: avoid special characters, newlines, or complex punctuation
             - Use goal IDs as strings: ["392"] not [392]

          DISCOVERY GUIDELINES:
          - Curate like a personalized Hacker News: 4-6 stand-out links TOTAL, not one per goal
          - Focus on 2-3 goals with HIGH priority or interesting context; it's fine to skip some goals this run
          - Use high-signal sources: Reddit, HN, Substack, niche forums, YouTube creators - not SEO sites
          - Include at least 1 adjacent/serendipitous discovery (related to goals but not obviously "how to do X")
          - Include URLs for all discoveries
          - Avoid sources or domains already shared recently (see recent_content above)
          - Match discoveries to goal learnings and user context (age, preferences, constraints)

          REFLECTION GUIDELINES:
          - Be specific: reference what you know (timelines, recent progress, details from learnings)
          - Keep it casual and playful: like texting a friend, not writing a journal prompt
          - Vary your style: questions, observations, playful nudges - never the same pattern twice
          - 10-20 words, easy to respond to
          - NEVER use "worth capturing" or "worth noting" - that sounds like a life coach
          - Examples:
            * "Has Sophie done anything new lately? Those 4-month changes happen fast."
            * "Any update on the kitchen timeline? I can dig into contractors whenever you're ready."
            * "3 weeks of early workouts! Anything starting to feel easier?"
          </task_instructions>

          After creating the task, you're done - the task will handle the rest.
          </feed_generation_task>
        PROMPT
      end

      # Build goal priorities based on recent coverage (what needs attention)
      # Note: Full goal context (learnings) is in system prompt
      def build_goal_priorities_xml(goals:, user_agent:)
        discovery_counts = FeedInsight.recent_discovery_goal_ids(user_agent, days: 7)

        priorities = goals.map do |goal|
          discoveries_7d = discovery_counts[goal.id] || 0
          priority = case discoveries_7d
                     when 0..2 then 'high'
                     when 3..5 then 'medium'
                     else 'low'
                     end
          "    <goal id=\"#{goal.id}\" title=\"#{xml_safe(goal.title)}\" priority=\"#{priority}\" discoveries_7d=\"#{discoveries_7d}\"/>"
        end.join("\n")

        "<goal_priorities note=\"Focus on high priority goals\">\n#{priorities}\n</goal_priorities>"
      end

      # Build recent coverage context (what was recently asked/shared)
      # Shows what's been covered to keep feed fresh - no hard blocking, just awareness
      def build_recent_coverage_xml(user_agent:, recent_insights:)
        recent_reflections = recent_insights.select(&:reflection?).first(5)
        recent_discoveries = recent_insights.select(&:discovery?).first(12)

        reflections_xml = if recent_reflections.any?
          recent_reflections.map do |r|
            goal_ids = (r.goal_ids || []).join(',')
            prompt_text = xml_safe(r.metadata['prompt']&.truncate(80))
            "      <asked date=\"#{r.created_at.strftime('%b %d')}\" goals=\"#{goal_ids}\">#{prompt_text}</asked>"
          end.join("\n")
        else
          "      <none/>"
        end

        discoveries_xml = if recent_discoveries.any?
          recent_discoveries.map do |d|
            # Include source domain for freshness variety
            url = d.metadata['url']
            domain = url.present? ? URI.parse(url).host&.gsub(/^www\./, '') : nil rescue nil
            source_attr = domain ? " source=\"#{xml_safe(domain)}\"" : ""
            title_text = xml_safe(d.metadata['title']&.truncate(60))
            "      <shared date=\"#{d.created_at.strftime('%b %d')}\"#{source_attr}>#{title_text}</shared>"
          end.join("\n")
        else
          "      <none/>"
        end

        <<~XML.strip
          <recent_content note="Keep feed fresh by varying topics and sources">
            <reflections_asked note="Pick different angles">
          #{reflections_xml}
            </reflections_asked>
            <discoveries_shared note="Vary topics and sources for freshness">
          #{discoveries_xml}
            </discoveries_shared>
          </recent_content>
        XML
      end

      # Build user preferences from UserAgent learnings (source preferences, etc.)
      def build_user_preferences_xml(user_agent:)
        return "" unless user_agent&.learnings&.any?

        learnings = user_agent.learnings.map { |l| "    <preference>#{xml_safe(l['content'])}</preference>" }.join("\n")

        <<~XML.strip
          <user_preferences note="Include these in task instructions">
          #{learnings}
          </user_preferences>
        XML
      end
    end
  end
end
