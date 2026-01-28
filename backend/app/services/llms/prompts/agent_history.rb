# frozen_string_literal: true

module Llms
  module Prompts
    # Agent History Summarization Prompts
    # Generates concise summaries capturing key facts and outcomes from agent sessions
    module AgentHistory
      module_function

      def system_prompt
        <<~PROMPT
          You write one-sentence conversation summaries for an AI assistant's memory.

          Your task: Summarize the KEY CONTEXT the assistant should remember.

          FOR USER CONVERSATIONS:
          Start with "User asked about...", "User mentioned...", or "Discussed..."
          Focus on: Questions asked, preferences shared, decisions made.

          Examples of GOOD summaries (user conversations):
          - "User asked about meal planning for picky eaters."
          - "User mentioned Sophie is having daycare trouble."
          - "User asked for workout routines under 20 minutes."
          - "Discussed sleep tips - user wants evidence-based advice."
          - "User shared that they prefer Substack over YouTube."
          - "User asked about Spanish learning podcasts for commuting."
          - "User mentioned budget is tight this month."
          - "Discussed baby milestones - Sophie is 4 months old."

          FOR AUTONOMOUS CHECK-INS (no user messages):
          Start with "Checked on..." or "Noticed..." or "Updated..."
          Focus on: What was discovered, what changed, what's noteworthy.
          Include specific details that help continue conversations later.

          Examples of GOOD summaries (autonomous):
          - "Checked on job postings - found 3 new React positions matching preferences."
          - "Noticed step count down 20% this week, may want to discuss activity level."
          - "Updated learning progress - user completed 2 Spanish lessons this week."
          - "Checked sleep patterns - consistent 7h average, no issues detected."
          - "Reviewed fitness goal - on track for monthly target."

          BAD summaries (avoid these):
          - "User created tasks" ← WRONG: users ask questions, the assistant creates tasks
          - "Tasks were initiated" ← WRONG: too technical, focus on the topic
          - "The assistant created a note" ← WRONG: focus on what user wanted
          - "Ran daily check-in" ← WRONG: describes action, not outcome
          - "Checked goal" ← WRONG: no useful context

          These summaries help your future self pick up conversations naturally.
        PROMPT
      end

      def user_prompt(llm_history:, tool_names:)
        user_messages = extract_user_messages(llm_history)
        topics_discussed = extract_topics(llm_history)
        tool_outcomes = extract_tool_outcomes(llm_history)

        if user_messages.present?
          <<~PROMPT
            Summarize this conversation in ONE sentence.

            USER SAID:
            #{user_messages}

            TOPICS: #{topics_discussed.presence || 'None identified'}

            Write your summary (start with "User asked..." or "User mentioned..." or "Discussed..."):
          PROMPT
        else
          <<~PROMPT
            Summarize this autonomous session in ONE sentence.

            TOOLS USED: #{tool_names.join(', ').presence || 'None'}
            OUTCOMES: #{tool_outcomes.presence || 'No specific outcomes'}
            TOPICS: #{topics_discussed.presence || 'None identified'}

            Write your summary (start with "Checked on..." or "Noticed..." or "Updated..."):
            Focus on what was discovered or what changed, not the actions taken.
          PROMPT
        end
      end

      # Extract actual user messages (not tool results)
      def extract_user_messages(llm_history)
        messages = []
        llm_history.first(12).each do |msg|
          next unless msg['role'] == 'user'
          content = msg['content']

          if content.is_a?(String) && content.present?
            messages << "- #{content.truncate(200)}"
          elsif content.is_a?(Array)
            # Check for actual user text (not tool_result)
            content.each do |block|
              if block['type'] == 'text' && block['text'].present?
                messages << "- #{block['text'].truncate(200)}"
              end
            end
          end
        end
        messages.first(3).join("\n")
      end

      # Extract topics from tool usage (what was the conversation about)
      def extract_topics(llm_history)
        topics = []
        llm_history.first(12).each do |msg|
          next unless msg['role'] == 'assistant'
          content = msg['content']

          if content.is_a?(Array)
            content.each do |block|
              next unless block['type'] == 'tool_use'
              topic = summarize_tool_topic(block['name'], block['input'])
              topics << topic if topic.present?
            end
          end
        end
        topics.uniq.first(4).join(", ")
      end

      # Extract the TOPIC from tool usage (not the action)
      def summarize_tool_topic(tool_name, input)
        return nil unless input.is_a?(Hash)

        case tool_name
        when 'create_note'
          input['title'] || input[:title]
        when 'create_task'
          input['title'] || input[:title]
        when 'brave_web_search'
          query = input['query'] || input[:query]
          "searched: #{query}" if query
        when 'save_learning'
          content = input['content'] || input[:content]
          "learned: #{content.to_s.truncate(50)}" if content
        else
          nil
        end
      end

      # Extract meaningful outcomes from tool results (for autonomous sessions)
      def extract_tool_outcomes(llm_history)
        outcomes = []
        llm_history.first(12).each do |msg|
          next unless msg['role'] == 'user' && msg['content'].is_a?(Array)

          msg['content'].each do |block|
            next unless block['type'] == 'tool_result'
            content = block['content'].to_s.truncate(100)

            # Skip generic success messages that don't provide context
            next if content.match?(/^(Success|Done|Completed|OK|Created|Updated|Saved)/i)
            next if content.blank?

            outcomes << content
          end
        end
        outcomes.first(3).join('; ')
      end
    end
  end
end
