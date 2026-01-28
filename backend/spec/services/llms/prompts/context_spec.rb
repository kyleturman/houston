# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llms::Prompts::Context do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user, title: "Test Goal") }

  describe '.time' do
    it 'returns time context XML' do
      result = described_class.time

      expect(result).to include('<time_context>')
      expect(result).to include('<current_date>')
      expect(result).to include('<day_of_week>')
      expect(result).to include('<timezone>')
    end
  end

  describe '.notes' do
    context 'with goal notes' do
      before do
        create(:note,
          user: user,
          goal: goal,
          title: "Cooking Note",
          content: "Made lasagna yesterday",
          source: :user
        )
        create(:note,
          user: user,
          goal: goal,
          title: "Agent Note",
          content: "Researched Italian recipes",
          source: :agent
        )
      end

      it 'includes user notes with full content' do
        result = described_class.notes(goal: goal)

        expect(result).to include('<notes_context>')
        expect(result).to include('<user_notes>')
        expect(result).to include('Cooking Note')
        expect(result).to include('Made lasagna yesterday')
      end

      it 'includes recent agent notes as recent_research' do
        result = described_class.notes(goal: goal)

        expect(result).to include('<recent_research>')
        expect(result).to include('Agent Note')
        expect(result).to include('Researched Italian recipes')
      end

      it 'formats notes as XML with date attributes' do
        result = described_class.notes(goal: goal)

        expect(result).to match(/<note date="\d{4}-\d{2}-\d{2}"/)
        expect(result).to include('<title>')
        expect(result).to include('<content>')
      end
    end

    context 'with URL notes (web_summary)' do
      before do
        create(:note,
          user: user,
          goal: goal,
          title: "Article Title",
          content: "Check this out!",
          source: :user,
          metadata: {
            'source_url' => 'https://example.com/article',
            'web_summary' => 'This article discusses important concepts about web development.',
            'processing_state' => 'completed'
          }
        )
      end

      it 'includes both user commentary and web summary' do
        result = described_class.notes(goal: goal)

        expect(result).to include('<user_note>Check this out!</user_note>')
        expect(result).to include('<link_summary>This article discusses important concepts')
        expect(result).to include('<source_url>https://example.com/article</source_url>')
      end

      it 'includes SEO description fallback when summary not ready' do
        create(:note,
          user: user,
          goal: goal,
          title: "Pending Article",
          content: "Interesting link",
          source: :user,
          metadata: {
            'source_url' => 'https://example.com/pending',
            'processing_state' => 'pending',
            'seo' => { 'description' => 'A description from SEO metadata' }
          }
        )

        result = described_class.notes(goal: goal)

        expect(result).to include('<seo_description>A description from SEO metadata</seo_description>')
        expect(result).to include('<source_url>https://example.com/pending</source_url>')
      end

      it 'handles URL-only notes without commentary' do
        create(:note,
          user: user,
          goal: goal,
          title: "Just a Link",
          content: nil,  # URL was removed, no commentary
          source: :user,
          metadata: {
            'source_url' => 'https://example.com/no-commentary',
            'web_summary' => 'Summary of the linked content.'
          }
        )

        result = described_class.notes(goal: goal)

        # Check that this specific note doesn't have user_note (but other notes might)
        expect(result).to include('<link_summary>Summary of the linked content.</link_summary>')
        expect(result).to include('<source_url>https://example.com/no-commentary</source_url>')

        # Extract just the note for "Just a Link" and verify it has no user_note
        just_link_note = result[/Just a Link.*?<\/note>/m]
        expect(just_link_note).not_to include('<user_note>')
      end
    end

    context 'with older agent notes beyond recency window' do
      include ActiveSupport::Testing::TimeHelpers

      before do
        # Create recent agent note (within 7 day window)
        create(:note,
          user: user,
          goal: goal,
          title: "Recent Research",
          content: "Fresh findings about cooking",
          source: :agent
        )

        # Create older agent note (outside 7 day window)
        travel_to 10.days.ago do
          create(:note,
            user: user,
            goal: goal,
            title: "Old Recipe Research",
            content: "Old research content that should not appear in full",
            source: :agent
          )
        end
      end

      it 'includes recent agent notes in full' do
        result = described_class.notes(goal: goal)

        expect(result).to include('<recent_research>')
        expect(result).to include('Recent Research')
        expect(result).to include('Fresh findings about cooking')
      end

      it 'shows older agent notes only as titles in previous_research' do
        result = described_class.notes(goal: goal)

        expect(result).to include('<previous_research>')
        expect(result).to include('Old Recipe Research')
        expect(result).not_to include('Old research content that should not appear')
      end

      it 'includes guidance to use search_notes for details' do
        result = described_class.notes(goal: goal)

        expect(result).to include('use search_notes for details')
        expect(result).to include("don't duplicate")
      end
    end

    context 'with no notes' do
      it 'returns nil' do
        result = described_class.notes(goal: goal)
        expect(result).to be_nil
      end
    end

    context 'with UserAgent (unassigned notes)' do
      before do
        create(:note,
          user: user,
          goal: nil,  # Unassigned
          title: "Personal Note",
          content: "Random thought",
          source: :user
        )
      end

      it 'includes unassigned notes' do
        result = described_class.notes(user: user)

        expect(result).to include('<personal_notes>')
        expect(result).to include('Personal Note')
        expect(result).to include('Random thought')
      end
    end
  end

  describe '.learnings' do
    context 'with goal learnings' do
      before do
        goal.update!(learnings: [
          { id: 1, content: "User prefers morning workouts", created_at: 1.day.ago.iso8601 },
          { id: 2, content: "Has dietary restrictions: no dairy", created_at: 2.days.ago.iso8601 }
        ])
      end

      it 'includes learnings as XML' do
        result = described_class.learnings(goal: goal)

        expect(result).to include('<learnings>')
        expect(result).to include('User prefers morning workouts')
        expect(result).to include('Has dietary restrictions: no dairy')
      end

      it 'includes learning IDs and timestamps' do
        result = described_class.learnings(goal: goal)

        expect(result).to match(/<learning id="1"/)
        expect(result).to match(/timestamp="/)
      end

      it 'just returns learnings XML without extra notes' do
        result = described_class.learnings(goal: goal)

        # Should include the learnings XML but not extra guidance
        # Guidance is now in core.rb's learning_management section
        expect(result).to include('<learnings>')
        expect(result).not_to include('<learnings_note>')
      end
    end

    context 'with no learnings' do
      it 'returns empty string' do
        result = described_class.learnings(goal: goal)
        expect(result).to eq("")
      end
    end

    context 'with task that has goal with learnings' do
      let(:task) { create(:agent_task, user: user, goal: goal) }

      before do
        goal.update!(learnings: [
          { id: 1, content: "Test learning", created_at: 1.day.ago.iso8601 }
        ])
      end

      it 'retrieves learnings from parent goal' do
        result = described_class.learnings(task: task)

        expect(result).to include('Test learning')
      end
    end
  end

  describe '.agent_history' do
    context 'with archived sessions' do
      before do
        3.times do |i|
          goal.agent_histories.create!(
            agent_history: [{ 'role' => 'user', 'content' => "Message #{i}" }],
            summary: "Session #{i} summary",
            message_count: 1,
            token_count: 100,
            completed_at: i.days.ago
          )
        end
      end

      it 'includes agent history summaries' do
        result = described_class.agent_history(agentable: goal)

        expect(result).to include('<your_memory>')
        expect(result).to include('Session 0 summary')
        expect(result).to include('Session 1 summary')
        expect(result).to include('Session 2 summary')
      end

      it 'mentions search tool availability' do
        result = described_class.agent_history(agentable: goal)

        expect(result).to include('search_agent_history')
      end

      it 'limits to configured count' do
        # Create 10 histories
        10.times do |i|
          goal.agent_histories.create!(
            agent_history: [{ 'role' => 'user', 'content' => "Extra #{i}" }],
            summary: "Extra session #{i}",
            message_count: 1,
            token_count: 100,
            completed_at: (i + 5).days.ago
          )
        end

        result = described_class.agent_history(agentable: goal)

        # Should only include 5 (from Constants::AGENT_HISTORY_SUMMARY_COUNT)
        summary_count = result.scan(/Session \d+ summary|Extra session \d+/).length
        expect(summary_count).to eq(5)
      end
    end

    context 'with no agent history' do
      it 'returns empty string' do
        result = described_class.agent_history(agentable: goal)
        expect(result).to eq("")
      end
    end
  end

  describe 'integration: full system prompt includes all context' do
    before do
      # Create notes
      create(:note,
        user: user,
        goal: goal,
        title: "Meal Prep",
        content: "Cooked chicken and rice on Sunday",
        source: :user
      )

      # Add learnings
      goal.update!(learnings: [
        { id: 1, content: "User meal preps on Sundays", created_at: 1.day.ago.iso8601 }
      ])

      # Create agent history
      goal.agent_histories.create!(
        agent_history: [{ 'role' => 'user', 'content' => 'What should I cook?' }],
        summary: "User asked for cooking suggestions",
        message_count: 1,
        token_count: 50,
        completed_at: 2.days.ago
      )
    end

    it 'orchestrator builds complete system prompt with all context' do
      notes_text = described_class.notes(goal: goal)
      system_prompt = Llms::Prompts::Goals.system_prompt(
        goal: goal,
        notes_text: notes_text
      )

      # Should include time context (built inside Goals.system_prompt)
      expect(system_prompt).to include('<time_context>')

      # Should include notes
      expect(system_prompt).to include('Meal Prep')
      expect(system_prompt).to include('Cooked chicken and rice')

      # Should include learnings (built inside Goals.system_prompt)
      expect(system_prompt).to include('<learnings>')
      expect(system_prompt).to include('User meal preps on Sundays')

      # Should include agent history (built inside Goals.system_prompt)
      expect(system_prompt).to include('<your_memory>')
      expect(system_prompt).to include('User asked for cooking suggestions')

      # Should include goal context
      expect(system_prompt).to include('<goal>')
      expect(system_prompt).to include(goal.title)
    end
  end

  describe '.recent_tool_errors' do
    it 'counts errors in recent llm_history' do
      # Create longer history to pass the minimum length check (needs > 5 entries)
      goal.update!(llm_history: [
        { 'role' => 'user', 'content' => 'start' },
        { 'role' => 'assistant', 'content' => 'ok' },
        { 'role' => 'user', 'content' => 'next' },
        { 'role' => 'assistant', 'content' => 'doing' },
        { 'role' => 'user', 'content' => [{ 'type' => 'tool_result', 'content' => 'Error: failed to create' }] },
        { 'role' => 'assistant', 'content' => 'I will try again' },
        { 'role' => 'user', 'content' => [{ 'type' => 'tool_result', 'content' => 'Error: unknown keyword' }] }
      ])

      count = described_class.recent_tool_errors(goal)
      expect(count).to eq(2)
    end

    it 'returns 0 for short history' do
      goal.update!(llm_history: [
        { 'role' => 'user', 'content' => 'test' }
      ])

      count = described_class.recent_tool_errors(goal)
      expect(count).to eq(0)
    end
  end
end
