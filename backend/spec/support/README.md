# Test Support Files - Quick Reference

This directory contains reusable test utilities and helpers. All files are automatically loaded by RSpec.

## 🔐 Authentication

### Shared Contexts (Most Common)
```ruby
# Basic authentication (device + bearer token)
include_context 'authenticated user'
# Provides: user, device, auth_headers

# With a goal
include_context 'authenticated user with goal'
# Provides: user, device, auth_headers, goal

```

### Auth Helpers
```ruby
# Device Bearer token (most APIs)
auth_headers_for(device)  # Or just `auth_headers` from shared context

# JWT token (Feed API, Goals API)
user_jwt_headers_for(user)
```

**Quick Reference:**
| API | Auth Type | Helper |
|-----|-----------|--------|
| `/api/feed/*` | JWT | `user_jwt_headers_for(user)` |
| `/api/goals/*` | JWT | `user_jwt_headers_for(user)` |
| Most others | Bearer | `auth_headers_for(device)` |

## 🧪 Request Helpers

```ruby
# Parse JSON response
json_response           # Full JSON hash
jsonapi_data           # JSONAPI data node
jsonapi_attributes     # JSONAPI attributes

# Status expectations
expect_unauthorized    # 401
expect_forbidden       # 403
expect_not_found      # 404
expect_unprocessable  # 422
```

## 🤖 LLM Testing

### Default Behavior
**All LLM calls are automatically mocked** (safe, fast, free)

### Real LLM Tests
```ruby
it 'real test', :real_llm do
  skip_unless_real_llm_enabled  # Skips unless USE_REAL_LLM=true
  # Makes actual API calls - costs money!
end
```

**Note**: The `:real_llm` tag automatically:
- Skips the test unless `USE_REAL_LLM=true`
- Disables ALL mocking (LLM adapters, external services, etc.)
- Uses real API calls for everything

### Custom Mocks
```ruby
# Mock goal creation
mock_llm_service_response(
  mock_goal_creation_response(
    title: 'Test Goal',
    description: 'Test description'
  )
)

# Generic mock
mock_llm_service_response(
  mock_llm_response(
    content: 'Response text',
    tool_calls: [...]
  )
)
```

## 💬 Conversation Helpers

Canonical message builders for LLM tests. Use these instead of hand-rolling message hashes
to avoid format mismatches across Anthropic vs OpenAI-compatible adapters.

```ruby
# Simple messages (Anthropic content-array format)
user_message("Hello")
assistant_message("Hi there!")

# Messages with tool use (as stored in llm_history)
history_assistant_with_tool_use("Let me search.",
  tool_name: "brave_web_search", tool_id: "s1",
  input: { "query" => "test" }
)
history_tool_result(tool_id: "s1", content: "Search results...")

# Pre-built conversations
simple_conversation(topic: 'Rails testing')
conversation_with_tool_use(tool_name: 'brave_web_search', query: 'test')

# Archive helper — seeds thread messages using the actual Agentable constant
seed_thread_messages_for_archive(goal, user: user)
```

## 📝 Shared Examples

```ruby
# Test authentication requirement
it_behaves_like 'requires authentication' do
  let(:make_request) { get '/api/endpoint' }
end
```

## 🎯 Complete Example

```ruby
require 'rails_helper'

RSpec.describe 'My API', type: :request do
  # Setup authentication
  include_context 'authenticated user'
  
  # For JWT endpoints, add:
  let(:jwt_headers) { user_jwt_headers_for(user) }

  describe 'GET /api/my_endpoint' do
    it 'returns success' do
      get '/api/my_endpoint', headers: auth_headers
      
      expect(response).to have_http_status(:success)
      expect(jsonapi_data).to be_present
    end

    it_behaves_like 'requires authentication' do
      let(:make_request) { get '/api/my_endpoint' }
    end
  end
end
```

## 📚 Full Documentation

See `/TESTING_IMPROVEMENTS.md` for complete guide with:
- Detailed usage examples
- Migration guide from old patterns
- Best practices and anti-patterns
- Commands for running tests

## 🔍 File Reference

- **auth_helpers.rb** - Authentication utilities
- **request_spec_helper.rb** - Request testing helpers
- **llm_test_helper.rb** - LLM mocking and testing
- **shared_contexts/authentication.rb** - Reusable auth contexts
- **conversation_helpers.rb** - Canonical message builders and archive helpers
- **shared_examples/requires_authentication.rb** - Common test patterns

---

💡 **Tip for AI Agents**: When writing a new request spec, copy an existing one and modify. All patterns are consistent!
