# Agent System Architecture

**Central nervous system of Houston** - coordinates AI agents to help users achieve goals through autonomous research, task execution, and daily feed generation.

---

## Overview

The agent system enables three types of autonomous AI agents: **Goals**, **Tasks**, and **UserAgent**.

**Key principle:** All agents share the same execution engine (Orchestrator → CoreLoop → Tools) and inherent from the same Agentable concern, but differ in behavior, tools available, and lifecycle.

---

## Data Flow

### Execution Pipeline

```
User Action (iOS/API)
  ↓
ThreadMessage created → Database
  ↓
Orchestrator scheduled → Sidekiq
  ↓
Context built → Combines messages, notes, learnings
  ↓
CoreLoop started → ReAct pattern (LLM + Tools)
  ↓
Tools executed → Results returned to LLM
  ↓
Agent decides next action:
  - More tools? → Repeat
  - Send message? → User sees response
  - Task complete? → Exit naturally
  ↓
LLM history persisted
Runtime state updated (orchestrator_running: false)
```

### Example: User asks to create Note for Goal

1. **User types message** "Can you create a note?" (iOS) → POST `/api/goals/123/thread_messages`
2. **ThreadMessage created** with `processed: false`, `source: user`
3. **Orchestrator scheduled** via `Agents::Orchestrator.perform_async`
4. **Orchestrator checks** for unprocessed messages → finds user's message
5. **Context built** from: user message + notes + learnings + conversation history
6. **CoreLoop starts** ReAct iterations:
   - **Iteration 1:** LLM thinks "I should create a note" → calls `create_note` tool
   - **Iteration 2:** LLM sees "Note created successfully" → calls `send_message` to confirm
   - **Iteration 3:** LLM sees message sent → makes no tool calls → **natural completion**
7. **Orchestrator releases lock**, updates `runtime_state`
8. **iOS receives** message via SSE streaming

### How Agents Know When to Stop

**Natural completion** = LLM response with **no tool calls**

```ruby
# CoreLoop line 143
if tool_calls.blank?
  Rails.logger.info("Agent completed naturally - no more tool calls")
  natural_completion = true
  break
end
```

**Additional stopping conditions:**
- **Conversational agents** (Goal, UserAgent): Stop after `send_message` tool
- **Task agents**: Stop after max iterations or history length
- **Safety limits**: Max execution time, repetitive tool usage
- All set in constants.rb

**Why this works:** ReAct pattern allows LLM to reason about task completion. When LLM has accomplished its goal, it simply doesn't call any more tools.

---

## Thread Messages vs LLM History

To keep the chat clean and allow the agent to work, the agent shows tool activity or can decide separately to send the user a text bases message. This means there are two parallel data streams with different purposes:

### ThreadMessage (User-Visible Conversation)

```ruby
# app/models/thread_message.rb
# Polymorphic: belongs_to :agentable (Goal, AgentTask, UserAgent)

# Fields:
source: [:user, :agent, :error]       # Who created it
message_type: [:text, :tool]          # Regular message or tool activity
content: string                       # The actual message
metadata: json                        # Tool details, references, etc.
processed: boolean                    # Orchestrator consumed it?
```

**Purpose:** User-facing conversation and tool activity display
- User messages ("Add note about X")
- Agent messages (sent via `send_message` tool)
- Tool activity cells (create_note, web_search progress)

**Streamed to iOS** via SSE for real-time UI updates.

### LLM History (Agent Context)

```ruby
# Stored in agentable.llm_history (JSONB array)

# Format:
[
  { role: 'user', content: 'Create note about X' },
  { role: 'assistant', content: [
      { type: 'text', text: 'I will create that note' },
      { type: 'tool_use', id: '123', name: 'create_note', input: {...} }
    ]
  },
  { role: 'user', content: [
      { type: 'tool_result', tool_use_id: '123', content: 'Success' }
    ]
  }
]
```

**Purpose:** Complete conversation context for LLM
- Every user message
- Every assistant response (text + tool calls)
- Every tool result
- **Never shown directly to users** (internal to agent)

### Key Differences

| Aspect | ThreadMessage | LLM History |
|--------|--------------|-------------|
| **Visibility** | User sees in iOS | Internal to agent |
| **Content** | User messages + sent messages + tool cells | Full ReAct conversation |
| **Tool Results** | Not stored (shown as progress) | Every tool result stored |
| **Streaming** | Via SSE to iOS | Persisted to DB |
| **Lifecycle** | Permanent (conversation log) | Can be trimmed and compressed |

**Example:** Agent creates 3 notes via tools
- **ThreadMessage:** 3 tool activity cells ("Creating note...")
- **LLM History:** 6 entries (3 tool_use + 3 tool_result)

---

## Agent History (Session Archiving)

**Episodic memory for cost optimization** - archives old conversations into searchable summaries, dramatically reducing token usage.

### Why It Exists

Without archiving, `llm_history` grows unbounded and every message in history gets sent on each API call. After 100 messages, you're sending 15K+ tokens per call. Agent history solves this by:

1. **Time-based sessions:** Archives conversation after 30 minutes of inactivity (or when feed completes)
2. **Summarization:** Compresses archived sessions into 2-3 sentence summaries
3. **Searchable storage:** Keeps full conversation in JSONB for deep retrieval when needed

### How It Works

```ruby
# Automatic archiving happens when:
# 1. Session timeout: 30 minutes since last message (Orchestrator checks on each run)
# 2. Feed generation: Immediately after feed completes

# Session lifecycle:
User sends message → llm_history grows → Time passes → Archive triggered
  → LLM generates summary → AgentHistory created → llm_history cleared

# Next message starts fresh session with summaries in context
```

### Storage

```ruby
# AgentHistory model (polymorphic: Goal, UserAgent, or AgentTask)
agent_history: jsonb      # Full conversation (JSONB + GIN index for search)
summary: text             # 2-3 sentence summary for context
completion_reason: string # 'session_timeout' | 'feed_generation_complete'
message_count: integer    # Metadata
token_count: integer      # Estimated tokens
started_at: datetime
completed_at: datetime
```

**Context strategy:**
- Last 5 session summaries included in system prompt
- Agent can `search_agent_history` tool for details from older conversations
- Active `llm_history` stays unbounded (will be next session archived)

### Search Tool

```ruby
# Available to Goals and UserAgent (not Tasks - they're ephemeral)
search_agent_history(query: "finances", timeframe: "last_month")

# Returns up to 5 matching sessions with summaries
# Searches both summary text and full conversation JSONB
```

### Configuration

```ruby
# constants.rb
SESSION_TIMEOUT = ENV.fetch('AGENT_SESSION_TIMEOUT', '30').to_i.minutes
AGENT_HISTORY_SUMMARY_COUNT = ENV.fetch('AGENT_HISTORY_SUMMARY_COUNT', '5').to_i
```

### Key Implementation Details

- **Summarization:** Uses cheap model (`use_case: :summaries`), falls back to user message extraction if LLM fails
- **Concurrency:** `with_lock` prevents double-archiving from race conditions
- **Dynamic tool:** `search_agent_history` only available when `agentable.agent_histories.exists?`
- **No task archiving:** Tasks are short-lived and don't accumulate history

### Tests

- `spec/models/concerns/agentable_agent_history_spec.rb` - Session management, archiving
- `spec/integration/agent_history_lifecycle_spec.rb` - Timeout & feed archiving triggers
- `spec/services/tools/system/search_agent_history_spec.rb` - Search functionality
- `spec/integration/agent_history_real_llm_spec.rb` - Real API validation (`USE_REAL_LLM=true`)

---

## Agent Types in Detail

### Goal Agent

**Behavior:** Conversational assistant for a specific goal
- **Status:** `working`, `waiting`, `archived`
- **Lifecycle:** Long-lived (days/weeks/months/forever)
- **Stops after:** `send_message` tool (conversational) or no tools are called (natural completion)
- **Creates tasks as sub-agents:** Creates instructions for and spins off AgentTask
- **System Tools:** Can send messages, save and update learnings, and create tasks
- **Goal Tools:** Users can enable or disable available MCP tools on a per goal basis

**Use case:** User talks to "Travel Planning" goal → goal agent can answer in thread message, create notes, or spin off tasks

### Agent Task

**Behavior:** Autonomous background research with generated instructions and minimal context
- **Status:** `active`, `completed`, `paused`, `cancelled`
- **Context:** More focused: doesn't have any context from notes or learnings, only goal description and instructions
- **Lifecycle:** Short-lived (seconds/minutes)
- **Stops after:** Max iterations (20) or completes objective and returns no tools (natural completion)
- **System Tools:** Cannot send messages, save and update learnings, or create tasks
- **MCP Tools:** Whatever tools parent Goal has enabled

**Use case:** Goal creates task "Research hotels in Tokyo" → task autonomously searches web, creates summary note saved back to goal

**Key difference:** Tasks **don't chat** - they execute and complete. Goal prompts them with specific instructions, they execute, done.

### User Agent

**Behavior:** Personal assistant across all goals
- **Status:** ❌ **No status enum** (always active and ready to help user)
- **Lifecycle:** Permanent (one per user)
- **Stops after:** `send_message` tool (conversational) or no tools are called (natural completion)
- **System Tools:** Can send messages, save and update learnings, or create tasks
- **MCP Tools:** Has access to all avaialble MCP tools unless otherwise disabled in code

**Use case:** Feed generation asks "What happened across all my goals today?" → UserAgent synthesizes insights from all goals

**Critical:** UserAgent has **no `.waiting?` or `.active?` methods** - check `llm_history.any?` instead.

---

## File Responsibilities

### Core Execution (Read in Order)

**`orchestrator.rb`** (~450 lines) - Main coordinator
- Job scheduling (Sidekiq)
- Context building (messages + notes + learnings)
- Execution locking (prevent duplicate runs)
- Error handling & retry scheduling
- Feed generation coordination

**Key methods:**
- `perform(agentable_type, agentable_id, context)` - Main entry
- `build_context_message` - Decides what message to send LLM based on `context['type']`
- `claim_execution_lock!` / `release_execution_lock!` - Prevents duplicates

**Context `type` vs `origin_type`:**
- `context['type']` controls orchestrator execution mode (`'feed_generation'`, `'agent_check_in'`). Only the **original agentable** should have this — it determines which prompt builder runs.
- When a parent creates child tasks via `create_task`, `type` is mapped to `origin_type` in the child's `context_data`. This preserves provenance without triggering the child's execution mode dispatch. See `CreateTask#extract_inheritable_context`.

---

**`core_loop.rb`** (~470 lines) - ReAct implementation
- LLM API calls via `Llms::Service.agent_call`
- Tool extraction & execution
- Natural completion detection
- Streaming to iOS (SSE events)
- History management

**Key methods:**
- `run!(message:, system_prompt:, max_iterations:)` - Main loop
- `execute_tool_calls(tool_calls)` - Runs tools, returns results
- `handle_agent_event(event, turn_id)` - Processes streaming events

**The loop:** LLM → Tools → Results → LLM → ... → No tools? Done!

---

**`error_handler.rb`** (~270 lines) - Retry & recovery
- Determines if error is retryable
- Exponential backoff calculation
- Error message creation (with countdown metadata for iOS)
- Retry scheduling (Sidekiq for Goals/UserAgent, pause for Tasks)
- Max retry enforcement

**Handles:**
- Rate limits (5 retries, 10s base delay)
- Network errors (3 retries, 10s base)
- Other errors (2 retries, 10s base)

---

**`constants.rb`** (~165 lines) - Configuration centralization
- CoreLoop limits (max iterations, execution time, history length)
- Retry configuration (delays, max attempts, jitter)
- Health monitor thresholds
- **All magic numbers live here** - no hardcoded values in logic

---

**`health_monitor.rb`** (~315 lines) - System health & recovery
- Runs every 5 minutes (Sidekiq Cron)
- Detects stuck orchestrators (running > 30 minutes)
- Cancels zombie Sidekiq jobs
- Retries paused tasks
- Expires old paused tasks (24 hours)
- Cleans up completed tasks (15 days)

Prevents resource leaks from crashed/stuck agents

---

## LLM Providers & Prompts
Agents are configured to be provider and model agnostic, having each call go through a central LLM service that handles the provider selection and execution.

### LLM Service (`app/services/llms/`)

**Public API:** `Llms::Service` (never call adapters directly!)

```ruby
# For agents (structured streaming)
Llms::Service.agent_call(
  agentable: goal,
  user: user,
  system: system_prompt,
  messages: llm_history,
  tools: provider_tools
) do |event|
  # Events: :think, :tool_start, :tool_complete
end

# For simple calls (chat, creation)
Llms::Service.call(
  system: system_prompt,
  messages: messages,
  tools: tools,
  user: user
)
```

**Adapters** (`llms/adapters/`) - Provider implementations
- `anthropic_adapter.rb` - Claude (Anthropic)
- `openai_adapter.rb` - OpenAI
- `ollama_adapter.rb` - Ollama (local models)
- `openrouter_adapter.rb` - OpenRouter (multi-provider)

Each adapter handles:
- Provider-specific API format
- Streaming event parsing
- Tool call extraction
- Cost tracking

### Prompt System (`app/services/llms/prompts/`)

**Organized by agent type:**

```ruby
Llms::Prompts::Goals.system_prompt(goal:, notes_text:)
  → Full system prompt for goal agent

Llms::Prompts::Tasks.system_prompt(goal:, task:, notes_text:)
  → Task-specific instructions

Llms::Prompts::UserAgent.system_prompt(user:, notes_text:)
  → Cross-goal assistant prompt
```

**Context builders** (`context.rb`):
```ruby
Llms::Prompts::Context.time
  → <time_context>...</time_context>

Llms::Prompts::Context.notes(goal: goal)
  → <notes_context>...</notes_context>

Llms::Prompts::Context.learnings(goal: goal)
  → <learnings>...</learnings>
```

**All prompts use XML formatting** for clear structure and reliable parsing.

---

## Safety Measures

### 1. Execution Locks (Prevent Duplicate Agents)

```ruby
# Agentable concern
def claim_execution_lock!
  return false if agent_running?  # Already locked

  update_column(:runtime_state, {
    orchestrator_running: true,
    orchestrator_started_at: Time.current,
    orchestrator_job_id: job_id
  })
  true
end
```

**Prevents:** Two orchestrators for same goal running simultaneously

### 2. Iteration Limits (Prevent Infinite Loops)

```ruby
# Constants
MAX_ITERATIONS = 20                 # Hard stop
MAX_SAME_TOOL_CONSECUTIVE = 5       # Same tool used 5x
MAX_EXECUTION_TIME = 10.minutes     # Wall clock limit
MAX_TASK_HISTORY_LENGTH = 20        # Task-specific (tasks are short!)
```

**CoreLoop checks these every iteration** and exits gracefully if exceeded.

### 3. Health Monitor (Zombie Recovery)

- **Stuck orchestrators:** Running > 30 minutes → cancel Sidekiq job, release lock
- **Stale tasks:** No updates in 2+ hours (prod) / 1 hour (dev) → mark completed
- **Stale goals:** No updates in 6+ hours (prod) / 3 hours (dev) → mark waiting
- **Paused tasks:** Retry when ready, expire after 24 hours

### 4. Retry Strategy (Graceful Degradation)

**Two-tier approach:**
1. **Immediate retries** (CoreLoop): 2 retries with 1.5s delay for transient rate limits
2. **Delayed retries** (Orchestrator): Exponential backoff with max attempts

**After max retries:** Error message updated to "Failed permanently" (`retryable: false`)

### 5. Cost Tracking

Every LLM call logs:
- Input tokens, output tokens, total cost
- Provider (Anthropic/OpenAI/Ollama/OpenRouter)
- Model used
- Stored in `user.total_llm_cost`

---

## Adding a New Agent Type

**Example:** Add "ProjectAgent" for project management

### 1. Create Model with Agentable

```ruby
# app/models/project_agent.rb
class ProjectAgent < ApplicationRecord
  include Agentable

  belongs_to :user

  enum :status, { active: 0, paused: 1, archived: 2 }

  def agent_type
    'project'  # Identifies this agent type
  end

  def conversational?
    true  # Stops after send_message
  end

  def associated_goal
    nil  # Or link to a goal if relevant
  end
end
```

### 2. Add System Prompt

```ruby
# app/services/llms/prompts/project_agent.rb
module Llms
  module Prompts
    module ProjectAgent
      module_function

      def system_prompt(project:, notes_text:)
        core = Llms::Prompts::Core.system_prompt

        <<~PROMPT
          #{core}

          <role>
          You are a project management assistant for: #{project.name}
          </role>

          #{notes_text}

          <tools>
          Use create_task to break down projects into actionable tasks.
          Use send_message to update the user on progress.
          </tools>
        PROMPT
      end
    end
  end
end
```

### 3. Update Orchestrator

```ruby
# orchestrator.rb - build_system_prompt method
def build_system_prompt
  if @agentable.goal?
    # existing code
  elsif @agentable.task?
    # existing code
  elsif @agentable.project?  # ADD THIS
    notes_text = Llms::Prompts::Context.notes(project: @agentable)
    Llms::Prompts::ProjectAgent.system_prompt(project: @agentable, notes_text: notes_text)
  else
    raise "Unknown agentable type: #{@agentable.class.name}"
  end
end
```

### 4. Configure Tools (if needed)

```ruby
# app/services/tools/registry.rb
def enabled_tools_for_context(context)
  case context
  when :project
    all_tools.select { |t|
      ['send_message', 'create_task', 'manage_learning'].include?(t.metadata[:name])
    }
  # ... existing code
  end
end
```

### 5. Add Migration

```bash
rails g migration CreateProjectAgents user:references name:string status:integer
rails g migration AddAgentFieldsToProjectAgents
```

```ruby
# In migration
add_column :project_agents, :llm_history, :jsonb, default: []
add_column :project_agents, :runtime_state, :jsonb, default: {}
add_column :project_agents, :learnings, :jsonb, default: []
```

**That's it!** ProjectAgent now works with existing orchestrator, CoreLoop, tools, streaming, etc.

---

## Debugging Guide

### When Agent Gets Stuck

**Symptoms:**
- Task running > 2 minutes
- Same tool called repeatedly
- No `send_message` or completion

**Debugging steps:**

**1. Check LLM History** (most important!)
```ruby
# Rails console
agent = Goal.find(123)
agent.llm_history.each_with_index { |entry, i| puts "#{i}: #{entry['role']} - #{entry['content'].class}" }
```

Look for:
- Tool results present? (Should see `tool_result` entries)
- Repetitive patterns? (Same tool_use multiple times)
- Growing history? (Should plateau after 10-20 entries for simple tasks)

**2. Check Runtime State**
```ruby
agent.runtime_state
# => {
#   "orchestrator_running" => true,
#   "orchestrator_started_at" => "2025-10-29T12:00:00Z",
#   "orchestrator_job_id" => "abc123"
# }
```

If `orchestrator_running: true` for > 10 minutes → stuck!

**3. Check Sidekiq Job**
```ruby
# Is job actually running?
Sidekiq::Workers.new.each do |process_id, thread_id, work|
  puts "#{work['payload']['jid']}: #{work['queue']}"
end
```

**4. Check Tool Registry**
```ruby
registry = Tools::Registry.new(user: user, goal: goal)
registry.all_tools.map { |t| t.metadata[:name] }
# Should include expected tools
```

**5. Enable Debug Logging**
```ruby
# Set in .env or docker-compose
LOG_LEVEL=debug

# Or in console
Rails.logger.level = :debug
```

### Common Issues & Fixes

**Issue:** Agent loops forever calling same tool
- **Root cause:** Tool returns same error repeatedly
- **Fix:** Check tool implementation, ensure it returns helpful context

**Issue:** Agent doesn't see previous actions
- **Root cause:** LLM history not persisting
- **Fix:** Check `HistoryManager.add_*` calls in CoreLoop

**Issue:** Tools not available to agent
- **Root cause:** Tool registry filtering too aggressive
- **Fix:** Check `enabled_tools_for_context` in `registry.rb`

**Issue:** UserAgent crashes with NoMethodError
- **Root cause:** Calling `.waiting?` or `.active?` on UserAgent
- **Fix:** Use `llm_history.any?` instead

### Health Monitor Cleanup

If agents are stuck, HealthMonitor runs every 5 minutes:
```ruby
# Force it manually
Agents::HealthMonitor.new.perform
```

This will:
- Cancel stuck Sidekiq jobs
- Release execution locks
- Mark stale tasks as completed and stale goals as waiting

---

## Key Patterns & Conventions

### 1. Agentable Methods (Not Type Checking)

```ruby
# ❌ WRONG
if agentable.is_a?(Goal)
  do_something
elsif agentable.is_a?(AgentTask)
  do_something_else
end

# ✅ CORRECT
if agentable.conversational?
  do_something
elsif agentable.task?
  do_something_else
end
```

### 2. Instance vs Class Methods

```ruby
# ✅ CORRECT - CoreLoop needs instance state
core_loop = Agents::CoreLoop.new(user: user, agentable: goal, tools: tools)
core_loop.run!(message: message)

# ❌ WRONG
Agents::CoreLoop.run!(message: message)  # NoMethodError!
```

### 3. Streaming Events

```ruby
# Orchestrator publishes to stream_channel
Streams::Broker.publish(@stream_channel, event: :think, data: { text: "..." })

# iOS receives via SSE:
# event: think
# data: {"text": "I will create a note"}
```

### 4. Error Handling

```ruby
# Tools should return standardized format
{ success: true, observation: "Note created with 150 chars" }
{ success: false, error: "Note title required" }

# CoreLoop handles both gracefully
```
