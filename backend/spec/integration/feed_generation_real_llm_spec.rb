# frozen_string_literal: true

require 'rails_helper'

# End-to-end test: runs the full feed generation pipeline with a real LLM
# and verifies that FeedInsight records are actually created in the database.
#
# This catches the exact class of bug where the LLM runs but fails to call
# the generate_feed_insights tool (e.g., context/prompt issues).
#
# Cost: ~$0.10-0.20 per run
RSpec.describe 'Feed generation with Real LLM', :real_llm do
  before(:each) do
    skip_unless_real_llm_enabled

    unless ENV['LLM_AGENTS_MODEL'] && !ENV['LLM_AGENTS_MODEL'].empty?
      skip 'Feed generation test requires LLM_AGENTS_MODEL to be set'
    end
  end

  let(:user) { create(:user) }
  let(:user_agent) { user.user_agent }

  it 'produces FeedInsight records for a user with multiple goals' do
    puts "\n📰 FEED GENERATION END-TO-END TEST"
    puts "=" * 80

    # Set up goals with learnings to give the LLM material to work with
    goal1 = create(:goal,
      user: user,
      title: "Learn to play piano",
      description: "Learn piano from scratch, focusing on classical pieces",
      status: :working
    )
    goal1.add_learning("Started 3 weeks ago with basic scales")
    goal1.add_learning("Practicing 30 minutes daily")

    goal2 = create(:goal,
      user: user,
      title: "Run a half marathon",
      description: "Train for a half marathon in 3 months",
      status: :working
    )
    goal2.add_learning("Currently running 5K comfortably")
    goal2.add_learning("Following a beginner half-marathon training plan")

    puts "✅ Created 2 goals with learnings:"
    puts "   Goal 1: #{goal1.title} (#{goal1.learnings.count} learnings)"
    puts "   Goal 2: #{goal2.title} (#{goal2.learnings.count} learnings)"

    # Add some notes so the LLM has recent context
    Note.create!(user: user, goal: goal1, source: :agent,
      title: "Piano Practice Log",
      content: "Completed first week of Hanon exercises. Fingers are getting more agile.")
    Note.create!(user: user, goal: goal2, source: :agent,
      title: "Running Progress",
      content: "Ran 8K today without stopping. Pace was 6:30/km. Feeling good about the training plan.")

    puts "   Added 2 notes for context"

    # Set feed period on user_agent
    user_agent.set_feed_period!('morning')

    test_start = Time.current

    puts "\n🤖 Running feed generation via orchestrator..."

    begin
      old_level = Rails.logger.level
      Rails.logger.level = :debug

      orchestrator = Agents::Orchestrator.new
      orchestrator.perform(
        user_agent.class.name,
        user_agent.id,
        {
          'type' => 'feed_generation',
          'time_of_day' => 'morning',
          'scheduled' => true
        }
      )
    rescue => e
      puts "   ❌ ERROR: #{e.class}: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(10).join("\n   ")}"
      raise
    ensure
      Rails.logger.level = old_level if old_level
    end

    elapsed = Time.current - test_start
    puts "⏱️  Orchestrator took: #{elapsed.round(2)}s"

    # Check FeedInsight records created during this test
    insights = FeedInsight.where(user: user)
                          .where('created_at >= ?', test_start)

    reflections = insights.where(insight_type: :reflection)
    discoveries = insights.where(insight_type: :discovery)

    puts "\n📊 Results:"
    puts "   Total insights: #{insights.count}"
    puts "   Reflections: #{reflections.count}"
    puts "   Discoveries: #{discoveries.count}"

    if reflections.any?
      puts "\n💭 Reflections:"
      reflections.each do |r|
        puts "   - #{r.display_content.to_s.truncate(120)}"
        puts "     Goal IDs: #{r.goal_ids}"
      end
    end

    if discoveries.any?
      puts "\n🔍 Discoveries:"
      discoveries.each do |d|
        info = d.display_content
        puts "   - #{info[:title]}"
        puts "     #{info[:summary].to_s.truncate(100)}"
        puts "     URL: #{info[:url]}" if info[:url].present?
        puts "     Goal IDs: #{d.goal_ids}"
      end
    end

    # Core assertion: feed generation must produce insights
    expect(insights.count).to be >= 1,
      "Feed generation completed but created 0 FeedInsight records. " \
      "This is the exact failure mode we're testing for — the LLM ran " \
      "but never called generate_feed_insights."

    # All insights should have the correct period
    expect(insights.pluck(:time_period).uniq).to eq(['morning'])

    # Insights should reference at least one goal
    all_goal_ids = insights.flat_map(&:goal_ids).uniq
    expect(all_goal_ids).not_to be_empty,
      "Insights were created but none reference any goals"

    # Cost tracking
    test_cost = LlmCost.where(user: user).where("created_at >= ?", test_start).sum(:cost)

    puts "\n✅ TEST PASSED!"
    puts "   ✅ #{insights.count} FeedInsight record(s) created"
    puts "   ✅ All insights have time_period='morning'"
    puts "   ✅ Insights reference goal IDs: #{all_goal_ids}"
    puts "\n💰 Total Cost: #{LlmCost.format_cost(test_cost)}"
    puts "=" * 80
  end
end
