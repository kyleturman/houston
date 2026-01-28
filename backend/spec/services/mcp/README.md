# MCP Framework Test Suite

## Philosophy: Test the Seams, Not the Implementation

This test suite focuses on **integration points** where things could silently break, rather than testing implementation details. We have comprehensive manual tests that validate end-to-end functionality.

## Test Files

### 1. **`registry_tool_status_spec.rb`** (11 tests) ⭐ CRITICAL
**Why it exists:** Tests the bug we actually fixed - tool status detection.

**What it covers:**
- MCP tool result format: `{ content: [{ text: '{"success": true}' }] }`
- System tool format: `{ success: true }`
- Error formats: `{ isError: true }`, `{ error: "..." }`
- Edge cases: empty results, non-JSON text, implicit success

**What could break:**
- New MCP servers with different response formats
- Changes to status determination logic
- New error formats from external APIs

**Run with:** `bundle exec rspec spec/services/tools/registry_tool_status_spec.rb`

---

### 2. **`tool_routing_spec.rb`** (9 tests)
**Why it exists:** Multi-connection support is complex and could fail silently.

**What it covers:**
- Multiple connections to same server (user has 2 banks via Plaid)
- Tool-to-server mapping in ConnectionManager
- Goal-level server filtering (`enabled_mcp_servers`)
- Active vs disconnected connection filtering

**What could break:**
- Wrong credentials used for tool call
- Disabled server's tools still accessible
- Connection lookup failures with multiple connections

**Run with:** `bundle exec rspec spec/services/mcp/tool_routing_spec.rb`

---

### 3. **`credential_lifecycle_spec.rb`** (8 tests)
**Why it exists:** Credential management is security-critical and state-dependent.

**What it covers:**
- Connection state transitions (active → disconnected)
- Credential encryption and storage
- Metadata persistence
- Connection identifier uniqueness
- Multi-connection per server

**What could break:**
- Credentials leaked in plaintext
- Stale credentials used after disconnection
- Duplicate connections created
- Metadata lost on updates

**Run with:** `bundle exec rspec spec/services/mcp/credential_lifecycle_spec.rb`

---

## What We DON'T Test (And Why)

### ❌ Auth Providers (Deleted)
**Why not:** Simple pass-through code. If it breaks, manual tests will catch it immediately. Testing individual providers tests implementation, not behavior.

### ❌ Mcp::Server infrastructure (Deleted)
**Why not:** Low-level plumbing. If broken, everything obviously fails. Not worth testing.

### ❌ AuthService orchestration (Deleted)
**Why not:** Thin wrapper around providers. Manual end-to-end tests validate the full OAuth flow works.

---

## Manual Test Coverage

We have comprehensive manual tests in `/backend/tmp/`:

- **`test_plaid_automated_v2.rb`** - Full OAuth flow, token exchange, 12 sandbox accounts
- **`test_plaid_agent_integration.rb`** - Agent discovers 8 tools, invokes 5, creates notes
- **`test_status_detection_directly.rb`** - Direct status detection validation

These give us real API integration proof that everything works together.

---

## Running Tests

```bash
# Run all MCP tests
bundle exec rspec spec/services/mcp/

# Run just the critical status test
bundle exec rspec spec/services/tools/registry_tool_status_spec.rb

# Run with documentation format
bundle exec rspec spec/services/mcp/ --format documentation
```

---

## Test Maintenance

### When to Add Tests:

1. **New MCP server with different response format** → Add case to `registry_tool_status_spec.rb`
2. **Credential refresh/expiration logic** → Add to `credential_lifecycle_spec.rb`
3. **New routing strategy** → Add to `tool_routing_spec.rb`

### When NOT to Add Tests:

- New auth provider (covered by manual tests)
- Simple CRUD operations
- Infrastructure code that obviously fails when broken

---

## Test Data

All tests use Factory Bot with minimal setup:

```ruby
let(:user) { create(:user) }
let(:plaid_server) { McpServer.create!(name: 'plaid', ...) }
let(:connection) { create(:user_mcp_connection, user: user, mcp_server: plaid_server) }
```

No complex mocking or stubbing - we test real ActiveRecord behavior.

---

## Coverage Summary

**Total: 28 tests across 3 files**

- ✅ Tool status detection (critical bug fix)
- ✅ Multi-connection routing
- ✅ Credential lifecycle
- ✅ Goal-level filtering
- ✅ Connection state management

**What's NOT covered (intentionally):**
- Individual auth provider implementations
- HTTP mocking for external APIs
- Low-level infrastructure code

**Manual tests cover:** Full end-to-end OAuth, real API integration, agent behavior

---

**Last Updated:** October 26, 2025
**Status:** Production ready
