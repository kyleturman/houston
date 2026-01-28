# frozen_string_literal: true

# Canonical conversation builders for LLM tests.
#
# These helpers produce messages in the correct format for each provider layer:
#   - Anthropic (native): content arrays with typed blocks
#   - OpenAI-compatible: role + string content, tool_calls array
#
# Tests should use these builders instead of hand-rolling message hashes
# to avoid format mismatches that silently break when the adapter layer changes.
#
# Usage:
#   messages = [
#     user_message("Hello"),
#     assistant_message("Hi there!"),
#     assistant_message_with_tool_use("Let me search.", tool_name: "brave_web_search", tool_id: "s1", input: { query: "test" }),
#     tool_result_message(tool_id: "s1", content: "Search results..."),
#   ]

module ConversationHelpers
  # ── Simple messages ────────────────────────────────────────────────

  # Build a user message in Anthropic content-array format
  def user_message(text)
    { role: 'user', content: [{ type: 'text', text: text }] }
  end

  # Build an assistant message in Anthropic content-array format
  def assistant_message(text)
    { role: 'assistant', content: [{ type: 'text', text: text }] }
  end

  # ── Messages with tool use (Anthropic format) ─────────────────────

  # Build an assistant message that includes a tool_use block.
  # This is the canonical Anthropic format stored in llm_history.
  def assistant_message_with_tool_use(text = nil, tool_name:, tool_id:, input: {})
    content = []
    content << { 'type' => 'text', 'text' => text } if text.present?
    content << {
      'type' => 'tool_use',
      'id' => tool_id,
      'name' => tool_name,
      'input' => input
    }
    { role: 'assistant', content: content }
  end

  # Build a tool result message (user role, as Anthropic expects)
  def tool_result_message(tool_id:, content:)
    {
      role: 'user',
      content: [{
        'type' => 'tool_result',
        'tool_use_id' => tool_id,
        'content' => content
      }]
    }
  end

  # ── History-format messages (string keys, for llm_history storage) ─

  # Build a history-format user message (as stored in agentable.llm_history)
  def history_user_message(text)
    { 'role' => 'user', 'content' => text }
  end

  # Build a history-format assistant message
  def history_assistant_message(text)
    { 'role' => 'assistant', 'content' => text }
  end

  # Build a history-format assistant message with tool_use blocks
  # (as stored after normalize_response_for_history)
  def history_assistant_with_tool_use(text = nil, tool_name:, tool_id:, input: {})
    content = []
    content << { 'type' => 'text', 'text' => text } if text.present?
    content << {
      'type' => 'tool_use',
      'id' => tool_id,
      'name' => tool_name,
      'input' => input
    }
    { 'role' => 'assistant', 'content' => content }
  end

  # Build a history-format tool result
  def history_tool_result(tool_id:, content:)
    {
      'role' => 'user',
      'content' => [{
        'type' => 'tool_result',
        'tool_use_id' => tool_id,
        'content' => content
      }]
    }
  end

  # ── Archive helpers ────────────────────────────────────────────────

  # Seed thread messages to meet the archive threshold for conversational sessions.
  # References the actual constant from Agentable to stay in sync with production.
  def seed_thread_messages_for_archive(agentable, user:, count: nil)
    count ||= Agentable::MINIMUM_THREAD_MESSAGES_FOR_ARCHIVE
    count.times do |i|
      ThreadMessage.create!(
        agentable: agentable,
        source: i.even? ? 'user' : 'agent',
        content: "Message #{i + 1}",
        user: user
      )
    end
  end

  # ── Pre-built conversations ────────────────────────────────────────

  # A simple Q&A conversation (no tool calls)
  def simple_conversation(topic: 'Rails testing')
    [
      { 'role' => 'user', 'content' => "What are the best practices for #{topic}?" },
      { 'role' => 'assistant', 'content' => "Here are some best practices for #{topic}: use proper structure, follow conventions, and test thoroughly." }
    ]
  end

  # A conversation with tool use (triggers autonomous archiving)
  def conversation_with_tool_use(tool_name: 'brave_web_search', tool_id: 'search_1', query: 'test query')
    [
      { 'role' => 'user', 'content' => "Research #{query}" },
      history_assistant_with_tool_use(
        'Let me search for that.',
        tool_name: tool_name,
        tool_id: tool_id,
        input: { 'query' => query }
      ),
      history_tool_result(tool_id: tool_id, content: "Results for #{query}..."),
      { 'role' => 'assistant', 'content' => "Based on the search, here's what I found about #{query}." }
    ]
  end
end

RSpec.configure do |config|
  config.include ConversationHelpers
end
