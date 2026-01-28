# Backend Development Guide (Rails)

**Prerequisites:** Read `../CLAUDE.md` first.

This guide covers Rails patterns, agents, LLM service, orchestrator, tools, prompts, debugging, and testing.

---

## 📋 Quick Reference

### Most Common Tasks

**Adding a Tool?**
1. Create `app/services/tools/system/my_tool.rb`
2. Inherit from `BaseTool`, define `metadata`, `schema`, `execute`
3. Add to context in `registry.rb` `enabled_tools_for_context` (check which agents get it)
4. **Before writing prompt:** Verify tool exists for that agent type

**Changing Agent Behavior?**
1. Edit prompts in `app/services/llms/prompts/`
2. Goals → `goals.rb`, Tasks → `tasks.rb`, UserAgent → `user_agent.rb`
3. **Don't reference tools that don't exist** - check `registry.rb` first
4. Changes immediate (no restart)

**Agent Stuck?**
1. Check `goal.llm_history` - what does agent see?
2. Look for missing tool results or repeated actions
3. See "Debugging Orchestrator" section below

**Adding Domain Logic?**
1. Check if it applies to all agentables (Goal, AgentTask, UserAgent)
2. If yes → Add to `app/models/concerns/agentable.rb`
3. If specific → Add to individual model

**Real-Time Updates?**
1. Controllers: Call `publish_lifecycle_event('note_created', note)`
2. Uses `Streams::Broker` to publish to global SSE
3. iOS `StateManager` auto-refreshes views

### When Debugging

**Before trial-and-error:**
1. Read the error message completely + line number
2. Check the actual model file (`cat app/models/agent_task.rb`)
3. Search for existing patterns (`grep -r "similar_code" spec/`)
4. THEN make changes

**Don't assume columns exist** - AgentTask uses polymorphic `taskable` (taskable_type, taskable_id), not `user_agent_id`

---

## 🎨 The Rails Way

**Core Principle:** Business logic in **concerns**, not controllers. Controllers orchestrate, concerns implement.

**Concern class methods:** Call on an including class, not the module: `McpServer.slugify(name)` ✓, `Slugifiable.slugify(name)` ✗

### DRY with Agentable
```ruby
# ✅ CORRECT - Once in Agentable, used everywhere
module Agentable
  def accepts_messages?
    # Available to Goal, AgentTask, UserAgent
  end

  def associated_goal
    # Polymorphic logic in one place
  end
end

# ❌ WRONG - Logic in controller
class GoalsController
  def show
    if @goal.status == "waiting" && @goal.llm_history.empty?
      # Business logic doesn't belong here
    end
  end
end
```

### Domain Methods (Use These!)
- `agentable.associated_goal`
- `agentable.accepts_messages?`
- `agentable.message_rejection_reason`
- `agentable.should_start_orchestrator?`
- `agentable.streaming_channel`

```ruby
# ✅ CORRECT
@agentable.accepts_messages?

# ❌ WRONG - Type checking
if @agentable.is_a?(Goal) && @agentable.waiting?
```

---

## 🏗️ Architecture Overview

```
User sends message
  → Controller creates ThreadMessage
  → Triggers Orchestrator (Sidekiq job)
  → Orchestrator runs CoreLoop
  → CoreLoop executes ReAct pattern:
      1. LLM thinks + chooses tool
      2. Tool executes
      3. Result added to llm_history
      4. Repeat until done
  → Streams events to iOS via Redis pub/sub
```

**Key Components:**
- **Agentable** (`app/models/concerns/agentable.rb`) - Shared agent logic
- **Orchestrator** (`app/services/agents/orchestrator.rb`) - Coordinates execution, builds system prompts
- **CoreLoop** (`app/services/agents/core_loop.rb`) - ReAct pattern implementation
- **Tools Registry** (`app/services/tools/registry.rb`) - Context-based tool permissions
- **Llms::Service** (`app/services/llms/service.rb`) - LLM calls (public API)
- **Prompts** (`app/services/llms/prompts/`) - All agent prompts (XML)

### Agent Types & Delegation

**UserAgent** → Creates tasks for feed generation, responds to user messages across all goals
**Goal** → Creates tasks for research/work on specific goal
**AgentTask** → Executes work (standalone or goal-specific)
  - **Standalone tasks** (`goal: nil`): Created by UserAgent, use `standalone_system_prompt`
  - **Goal tasks** (`goal: present`): Created by Goal agents, use `system_prompt(goal:, task:)`

**Critical:** Tasks with/without goals have DIFFERENT tool access and system prompts. Check `task.goal.nil?` for conditional logic.

**Deep Dive:** See `app/services/agents/README.md` for comprehensive docs on data flow, ThreadMessage vs LLM history, agent types, and how to add new agent types.

### Agentable Model Status Differences

| Model | Status Enum | Status Methods |
|-------|-------------|----------------|
| **Goal** | `working`, `waiting`, `archived` | `.working?`, `.waiting?`, `.archived?` |
| **AgentTask** | `active`, `completed`, `paused`, `cancelled` | `.active?`, `.completed?`, etc. |
| **UserAgent** | ❌ **NO STATUS** | ❌ Use `llm_history.any?` instead |

**Common mistake:** Calling `user_agent.waiting?` - doesn't exist! Check `llm_history.any?` or `runtime_state` instead.

---

## 📡 API & Serialization

**Use JSON:API format** with `fast_jsonapi` gem:
```ruby
class NoteSerializer < ApplicationSerializer
  include StringIdAttributes
  set_type :note
  attributes :title, :content
  string_id_attribute :goal_id  # Foreign keys MUST be strings
  iso8601_timestamp :created_at
end
```

**CRITICAL:** Foreign key IDs serialize as **strings** (`string_id_attribute`), not integers.
- Why: JavaScript precision (safe only to 2^53-1), JSON:API spec, works with UUIDs
- Helper: `StringIdAttributes` concern provides `string_id_attribute`

**Schema changes (2-layer iOS update):**
1. Backend: Update serializer + tests (`app/serializers/`, `spec/requests/api/`)
2. iOS Layer 1 - API models: `ios/Sources/Core/Models/API/` (GoalAPI.swift, NoteAPI.swift, TaskAPI.swift)
3. iOS Layer 2 - Domain models: `ios/Sources/Core/Models/` (Goal.swift, Note.swift, Task.swift) + update `from(resource:)`
4. Bump `cacheVersion` in iOS APIClient
5. Run `make test` + `make ios-check`

---

## 🛠️ Commands

**⚠️ CRITICAL: ALL tests MUST run in docker-compose** - encryption credentials, Redis, etc. only available in docker.

**Backend-specific:**
```bash
# Rails console (test DB)
docker-compose exec -e RAILS_ENV=test backend bundle exec rails console

# Specific test file
docker-compose exec -e RAILS_ENV=test backend bundle exec rspec spec/models/user_spec.rb

# Real LLM test (costs money)
docker-compose exec -e RAILS_ENV=test -e USE_REAL_LLM=true backend bundle exec rspec spec/integration/feed_generation_real_llm_spec.rb
```

**NEVER run `rails` or `rspec` directly** - always use `docker-compose exec backend` prefix.

---

## 🔧 Tools

### Adding New System Tools

**Create file → auto-registers** (`app/services/tools/system/my_tool.rb`):
```ruby
class MyTool < BaseTool
  def self.metadata
    super.merge(name: 'my_tool', description: 'What it does', params_hint: 'param1 (required)')
  end

  def self.schema
    { type: 'object', properties: { param1: { type: 'string' } }, required: ['param1'], additionalProperties: false }
  end

  def execute(param1:)
    { success: true, observation: "Result for LLM" }
  end
end
```

### Tool Return Values

**System tools** → Use `observation` (human-readable context):
```ruby
{ success: true, observation: "Created note with 150 characters. Saved." }
```

**MCP tools** → Use `result` (raw data, LLM parses JSON):
```ruby
{ success: true, result: '{"balances": [...], "total": "$12,380"}' }
```

**CoreLoop priority:** `result` → `observation` → `'Success'`

### Tool Access by Context

Tools registry (`registry.rb`) determines tool availability by context:
- `:goal` - Goal agents (can create tasks, save ideas, schedule check-ins)
- `:task` - Task agents (goal tasks vs standalone tasks have DIFFERENT tools)
  - Goal tasks: Can't create tasks or generate feed insights
  - Standalone tasks (no goal): CAN generate feed insights, can't save ideas
- `:user_agent` - UserAgent (can create tasks, generate feed insights, send messages)

**Check before writing prompts:** Verify tool exists in registry for that context.

**Notes** (goal-specific): Last 50 user notes (full) + 20 agent notes (truncated). `search_notes` tool appears if >70 notes.

**Learnings** (cross-goal): All learnings in every prompt. Use `save_learning`/`manage_learning`.

---

## 🔄 Error Handling

### Retry Strategy (Two-Tier)

1. **Immediate** (CoreLoop): 2 retries, 1.5s delay (transient errors)
2. **Delayed** (Orchestrator): Exponential backoff by error type

**Max attempts** (`app/services/agents/constants.rb`):
- Rate limits: 5 attempts (10s base)
- Network/timeout: 3 attempts (10s base)
- Other: 2 attempts (10s base)

ThreadMessages include retry metadata with `next_retry_at` timestamp. iOS shows countdown timer. On success, ThreadMessage deleted for clean conversation. After max retries, marked failed permanently.

**All agentables** (Goal, AgentTask, UserAgent) support retries.

### Health Monitor

Runs every 5 min to cancel stuck orchestrators (>30min), mark stale tasks completed (2hr prod/1hr dev) and stale goals waiting (6hr prod/3hr dev), cleanup old completed tasks (>15 days). Cancels actual Sidekiq jobs to prevent zombies. Config: `app/services/agents/constants.rb`.

---

## 🤖 LLM Service

**Use `Llms::Service` - never call adapters directly** (`app/services/llms/service.rb`).

```ruby
# Simple calls (chat, goal creation)
Llms::Service.call(system: "prompt", messages: [...], tools: [...], user: user, stream: true)

# Agent execution (structured events)
Llms::Service.agent_call(agentable: goal, user: user, system: "prompt", messages: [...], tools: [...]) do |event|
  # :think, :tool_start, :tool_complete
end
```

**Instance pattern:**
```ruby
# ✅ CORRECT - Instantiate services with state
core_loop = Agents::CoreLoop.new(user: user, agentable: goal, tools: tools)
core_loop.run!(message: message, max_iterations: 50)

# ❌ WRONG - No class methods
CoreLoop.run!(...)  # NoMethodError!
```

---

## 📝 Prompts

**Location:** `app/services/llms/prompts/` (XML format, changes immediate - no restart)

```
├── core.rb              # Base (rarely edit)
├── context.rb           # Reusable XML builders
├── voice_and_tone.rb    # Content style
├── goals.rb             # Goal agent + creation chat
├── tasks.rb             # Task agent
└── user_agent.rb        # UserAgent
```

**Usage:**
```ruby
Llms::Prompts::Goals.system_prompt(goal: goal, notes_text: notes)
Llms::Prompts::Context.time  # Returns XML
Llms::Prompts::Context.learnings(goal: goal)  # Returns XML
```

---

## 🐛 Debugging Orchestrator

**ALWAYS check `llm_history` first** - it shows what the agent sees!

**Agent not responding?**
1. Check `goal.orchestrator_job_id` → nil? Never started
2. Check Sidekiq dashboard → stuck in queue?
3. Check `goal.execution_lock_id` → locked?

**Agent looping?**
1. Check `goal.llm_history` → missing tool results? Context not saving
2. Same tool >5 times? Tool returning wrong format
3. `llm_history` size >50? ReAct pattern broken

**Agent stopped mid-task?**
1. Logs show rate limit? Will auto-retry
2. UserAgent has **no status methods** - use `llm_history.any?`
3. ThreadMessages have retry metadata? Countdown in progress

**Debugging mindset:** Fix root causes (missing context), not symptoms (loop counter).

**Healthy agent:** 2-6 llm_history entries/iteration, 1-3 cycles for simple tasks, progressive tool use, same tool ≤3 times.

**Full guide:** `app/services/agents/README.md` (Debugging section)

---

## 🧪 Testing

**Test DB:** `life_assistant_test` (separate from dev)

```bash
# ✅ Test console
docker-compose exec -e RAILS_ENV=test backend bundle exec rails console

# ❌ Dev console (wrong!)
docker-compose exec backend bundle exec rails console
```

### Testing Strategy

**Mocked (Free):**
```bash
make test                         # All tests (~2s)
make test-smoke                   # Critical path (~1s)
```

**Real LLM (Costs $):**
```bash
make test-llm-provider            # ~$0.001
make test-llm-goal                # ~$0.03
make test-llm-create-goal         # ~$0.02-0.05
```

**When to run:**
- **Every commit:** `test-smoke`
- **After agent changes:** `test-llm-goal`
- **After prompts:** `test-llm-create-goal`
- **Before release:** Full suite

### Request Specs & Auth

**Integration tests need `type: :request`:**
```ruby
RSpec.describe 'Goals API', type: :request do
  include AuthHelpers

  let(:user) { create(:user) }
  let(:auth_headers) { user_jwt_headers_for(user) }  # JWT auth - use for ALL /api/* endpoints

  it 'returns goals' do
    get '/api/goals', headers: auth_headers
    expect(response).to have_http_status(:success)
  end
end
```

**Auth methods:**
- `user_jwt_headers_for(user)` → JWT auth (`User <token>`) - **use this for all API endpoints**
- `auth_headers_for(device)` → Device Bearer token - only for device-specific endpoints

**Before writing test auth:** Search existing specs: `grep -r "api/your_endpoint" spec/requests`

### Factory Associations

**Polymorphic names:** `ThreadMessage` → `agentable`, `AgentTask` → `taskable`. When unsure: `cat spec/factories/<model>.rb`

### Real LLM Tests

**Tag `:real_llm`, needs `USE_REAL_LLM=true`:**
```ruby
it 'completes conversation', :real_llm do
  skip 'Set USE_REAL_LLM=true (costs ~$0.05)' unless ENV['USE_REAL_LLM'] == 'true'
  result = Llms::Service.call(system: Llms::Prompts::Goals.creation_chat_system_prompt, tools: [...], user: user)
  expect(result[:content]).to be_present
end
```

**LLM history archiving:** After feed generation, `llm_history` → `agent_histories` table. Check `agent_histories` in tests, not `llm_history`.

---

## 📡 Real-Time Updates

**Controllers:** Publish lifecycle events for UI updates

```ruby
def create
  note = Note.create!(note_params)
  publish_lifecycle_event('note_created', note)
  render json: NoteSerializer.new(note).serializable_hash, status: :created
end

private
def publish_lifecycle_event(event_name, resource, extra_data = {})
  channel = Streams::Channels.global_for_user(user: current_user)
  data = resource ? resource_data(resource).merge(extra_data) : extra_data
  Streams::Broker.publish(channel, event: event_name, data: data)
end
```

**Events:** `note_created`, `note_updated`, `note_deleted`, `task_created`, `task_updated`, `task_completed`, `goal_created`, `goal_updated`, `goal_archived`

**iOS:** `StateManager` subscribes + auto-refreshes

---

## 🔄 Streaming (SSE)

**Agent chat events** (Redis pub/sub → SSE):
1. `tool_start` → iOS refreshes UI
2. `tool_progress` → Update cell
3. `tool_completion` → Finalize
4. `think` → Internal (iOS ignores)
5. `chunk` → User-facing text

**Data types:**
- **ThreadMessages** - User/agent messages + tool blocks (UI visible)
- **LLM history** - Full context (internal)

---

## ⚡ Feed Generation

All agents run in parallel (2-3x faster): `app/services/feeds/generator.rb`. CoreLoop delays + Sidekiq queueing + retries provide natural rate limiting.

---

## 🗂️ Key Files & Search Patterns

**When stuck, search existing code first:**
```bash
# Find auth patterns
grep -r "api/feed" spec/requests --include="*.rb" -A 20

# Find polymorphic associations
grep -r "belongs_to.*polymorphic" app/models --include="*.rb"

# Find tool definitions
grep -r "def self.metadata" app/services/tools/system --include="*.rb"

# Check model schema
cat app/models/agent_task.rb  # Not db/schema.rb first
```

**Key files:**
```bash
backend/app/models/concerns/agentable.rb              # Core agent logic
backend/app/models/agent_task.rb                      # Polymorphic taskable
backend/app/services/agents/**/*.rb                   # Agent system
backend/app/services/llms/service.rb                  # LLM public API
backend/app/services/llms/prompts/**/*.rb             # All prompts (XML)
backend/app/services/tools/registry.rb                # Tool context/permissions
backend/app/services/tools/system/**/*.rb             # System tools
backend/app/services/feeds/generator.rb               # Parallel feeds
backend/app/serializers/**/*_serializer.rb            # JSON:API serializers
backend/spec/support/auth_helpers.rb                  # Test auth patterns
```

**Critical to read:**
- `app/services/agents/README.md` - Comprehensive agent system guide
- `app/models/concerns/agentable.rb` - Shared agent logic
- `app/serializers/concerns/string_id_attributes.rb` - String ID pattern

---

## ✅ Checklist

1. **DRY** - Logic in concerns, not controllers
2. **Domain methods** - Use `agentable.accepts_messages?`
3. **LLM calls** - `Llms::Service.call` only
4. **Instantiate** - Services with state (e.g., `CoreLoop.new`)
5. **Prompts** - Edit `prompts/`, changes immediate
6. **Real-time** - `publish_lifecycle_event()` in controllers
7. **Test** - `make test-smoke` before commit
8. **Debug** - Check `llm_history` first
9. **UserAgent** - No status methods!
10. **Deletions** - `.destroy` (not `.delete`)
11. **Commands** - Always use `docker-compose exec backend bundle exec`
12. **String IDs** - Use `string_id_attribute` in serializers
13. **Schema changes** - Update backend serializer + iOS API models + domain models
14. **Rails way** - Follow conventions
15. **Restart server** - If key parts of Rails files are changed, restart the backend and sidekiq containers after you're done

**Related:** `../CLAUDE.md` (root) | `../ios/CLAUDE.md` (iOS)
