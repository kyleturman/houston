# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Prompt Caching with Real LLM' do
  let(:user) { create(:user) }

  describe 'Anthropic Claude prompt caching', :real_llm do
    before do
      model = ENV['LLM_AGENTS_MODEL'] || ''
      skip 'Prompt caching test requires Anthropic provider' unless model.start_with?('anthropic:') || model.empty?
    end

    it 'caches system prompt and tools across multiple calls' do
      skip 'Set USE_REAL_LLM=true to run this test' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n" + "="*80
      puts "🎯 TESTING PROMPT CACHING WITH REAL ANTHROPIC LLM"
      puts "="*80
      puts "⚠️  This test makes real LLM calls to verify caching behavior"

      # Create a goal for testing
      goal = create(:goal,
        user: user,
        title: "Learn Spanish",
        description: "Want to learn conversational Spanish for an upcoming trip.",
        status: :waiting
      )
      goal.add_learning("Prefers audio-based learning over reading")

      puts "\n✓ Created test goal: #{goal.title}"

      # Make first LLM call - this should write to cache
      puts "\n📝 Making first LLM call (cache write expected)..."
      start_cost = user.total_llm_cost

      result1 = Llms::Service.call(
        system: Llms::Prompts::Goals.system_prompt(goal: goal),
        messages: [{ role: 'user', content: 'What is the goal title?' }],
        user: user,
        agentable: goal
      )

      first_call_cost = user.total_llm_cost - start_cost

      # Get the first call's LLM cost record
      first_cost_record = LlmCost.where(user: user).order(:created_at).last

      puts "\n✓ First call completed"
      puts "  Input tokens: #{first_cost_record.input_tokens}"
      puts "  Output tokens: #{first_cost_record.output_tokens}"
      puts "  Cache write tokens: #{first_cost_record.cache_creation_input_tokens}"
      puts "  Cost: #{LlmCost.format_cost(first_call_cost)}"

      # Verify cache write occurred
      expect(first_cost_record.cache_creation_input_tokens).to be > 0,
        "First call should have cache_creation_input_tokens > 0"

      # Make second LLM call with same system prompt - should hit cache
      puts "\n📖 Making second LLM call (cache read expected)..."
      pre_second_cost = user.total_llm_cost

      result2 = Llms::Service.call(
        system: Llms::Prompts::Goals.system_prompt(goal: goal),
        messages: [{ role: 'user', content: 'What should I focus on?' }],
        user: user,
        agentable: goal
      )

      second_call_cost = user.total_llm_cost - pre_second_cost

      # Get the second call's LLM cost record
      second_cost_record = LlmCost.where(user: user).order(:created_at).last

      puts "\n✓ Second call completed"
      puts "  Input tokens: #{second_cost_record.input_tokens}"
      puts "  Output tokens: #{second_cost_record.output_tokens}"
      puts "  Cache read tokens: #{second_cost_record.cache_read_input_tokens}"
      puts "  Cost: #{LlmCost.format_cost(second_call_cost)}"

      # Verify cache read occurred
      expect(second_cost_record.cache_read_input_tokens).to be > 0,
        "Second call should have cache_read_input_tokens > 0"

      # Verify cost savings
      # Second call should be cheaper due to cache reads
      # Cache read cost is 0.1x vs cache write at 1.25x
      expect(second_call_cost).to be < first_call_cost,
        "Second call should cost less due to cache reads"

      # Calculate savings
      savings_percent = ((first_call_cost - second_call_cost) / first_call_cost * 100).round(1)

      puts "\n💰 Cost Comparison:"
      puts "  First call:  #{LlmCost.format_cost(first_call_cost)} (cache write)"
      puts "  Second call: #{LlmCost.format_cost(second_call_cost)} (cache read)"
      puts "  Savings:     #{savings_percent}%"

      # Verify substantial savings (should be ~60-80% savings on input tokens)
      expect(savings_percent).to be > 30,
        "Should see >30% cost savings from caching"

      puts "\n" + "="*80
      puts "✅ PROMPT CACHING TEST PASSED"
      puts "="*80
      puts "Summary:"
      puts "  • Cache write detected: #{first_cost_record.cache_creation_input_tokens} tokens"
      puts "  • Cache read detected: #{second_cost_record.cache_read_input_tokens} tokens"
      puts "  • Cost savings: #{savings_percent}%"
      puts "  • Caching is working correctly!"
      puts "="*80 + "\n"
    end

    it 'demonstrates caching across goal agent iterations' do
      skip 'Set USE_REAL_LLM=true to run this test' unless ENV['USE_REAL_LLM'] == 'true'

      puts "\n" + "="*80
      puts "🔄 TESTING CACHING ACROSS AGENT ITERATIONS"
      puts "="*80

      goal = create(:goal,
        user: user,
        title: "Test Caching",
        description: "Testing prompt caching with iterations",
        status: :waiting
      )

      puts "\n✓ Created test goal"

      # Get initial cost
      start_cost = user.total_llm_cost

      # Run CoreLoop with a simple task that will iterate
      tools = Tools::Registry.new(user: user, goal: goal, agentable: goal)
      loop_runner = Agents::CoreLoop.new(
        user: user,
        agentable: goal,
        tools: tools,
        stream_channel: nil
      )

      puts "\n🔁 Running CoreLoop (3 iterations expected)..."

      notes_text = Llms::Prompts::Context.notes(goal: goal)
      system_prompt = Llms::Prompts::Goals.system_prompt(goal: goal, notes_text: notes_text)

      result = loop_runner.run!(
        message: "Please create a task called 'Research Spanish apps' with instructions 'Find 3 popular Spanish learning apps'",
        system_prompt: system_prompt,
        max_iterations: 3
      )

      total_cost = user.total_llm_cost - start_cost

      puts "\n✓ CoreLoop completed"
      puts "  Iterations: #{result[:iterations]}"

      # Check all cost records from this run
      cost_records = LlmCost.where(user: user)
        .where("created_at >= ?", 10.seconds.ago)
        .order(:created_at)

      puts "\n📊 Caching breakdown by iteration:"
      cost_records.each_with_index do |record, idx|
        puts "  Iteration #{idx + 1}:"
        puts "    Input: #{record.input_tokens} | Output: #{record.output_tokens}"
        puts "    Cache write: #{record.cache_creation_input_tokens}"
        puts "    Cache read: #{record.cache_read_input_tokens}"
        puts "    Cost: #{record.formatted_cost}"
      end

      puts "\n💰 Total cost for #{result[:iterations]} iterations: #{LlmCost.format_cost(total_cost)}"

      # Verify caching pattern - cache reads prove caching is working
      total_cache_reads = cost_records.sum(&:cache_read_input_tokens)
      total_cache_writes = cost_records.sum(&:cache_creation_input_tokens)

      expect(total_cache_reads).to be > 0,
        "Should see cache reads across iterations (this proves caching is working)"

      puts "\n📈 Cache Statistics:"
      puts "  Total cache writes: #{total_cache_writes} tokens"
      puts "  Total cache reads: #{total_cache_reads} tokens"

      puts "\n✅ Caching across iterations verified!"
      puts "="*80 + "\n"
    end
  end
end
