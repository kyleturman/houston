# Database Guidelines

## Data Integrity & Deletion Best Practices

### Polymorphic Associations

The Houston system uses **polymorphic associations** for several models:

- `thread_messages` → `agentable` (Goal, AgentTask, or UserAgent)
- `llm_costs` → `agentable` (Goal, AgentTask, or UserAgent)
- `feed_items` → `referenceable` (various models)

**Important:** PostgreSQL cannot enforce foreign key constraints on polymorphic associations because they reference multiple tables. Instead, we rely on ActiveRecord's `dependent: :destroy` associations.

### Required: Always Use ActiveRecord for Deletions

**✅ CORRECT - Use ActiveRecord:**
```ruby
# In Rails console or application code
goal = Goal.find(123)
goal.destroy  # Triggers dependent: :destroy callbacks

# Or batch deletion with ActiveRecord
Goal.where(user_id: 456).destroy_all
```

**❌ WRONG - Direct SQL bypasses callbacks:**
```sql
-- This will orphan thread_messages and llm_costs!
DELETE FROM goals WHERE id = 123;

-- This will also orphan records
DELETE FROM goals WHERE user_id = 456;
```

### Why This Matters

When you delete via SQL:
- ❌ `dependent: :destroy` callbacks are **not triggered**
- ❌ Orphaned `thread_messages` remain in database
- ❌ Orphaned `llm_costs` remain in database
- ❌ Data corruption and wasted storage

When you delete via ActiveRecord:
- ✅ All `dependent: :destroy` associations are cleaned up
- ✅ Database integrity maintained
- ✅ No orphaned records

### Protected Relationships

The following cascades are enforced at the **database level** (safe with SQL):

**User deletions:**
- ✅ goals → CASCADE
- ✅ agent_tasks → CASCADE
- ✅ alerts → CASCADE
- ✅ devices → CASCADE
- ✅ feeds → CASCADE
- ✅ llm_costs → CASCADE
- ✅ notes → CASCADE
- ✅ thread_messages → CASCADE
- ✅ user_agents → CASCADE
- ✅ user_mcp_connections → CASCADE

**Goal deletions:**
- ✅ agent_tasks → CASCADE (database)
- ✅ notes → CASCADE (database)
- ✅ alerts → CASCADE (database)
- ⚠️ thread_messages → **APPLICATION ONLY** (use ActiveRecord)
- ⚠️ llm_costs → **APPLICATION ONLY** (use ActiveRecord)

**AgentTask deletions:**
- ✅ child_tasks → NULLIFY (database)
- ⚠️ thread_messages → **APPLICATION ONLY** (use ActiveRecord)
- ⚠️ llm_costs → **APPLICATION ONLY** (use ActiveRecord)

**UserAgent deletions:**
- ⚠️ thread_messages → **APPLICATION ONLY** (use ActiveRecord)
- ⚠️ llm_costs → **APPLICATION ONLY** (use ActiveRecord)

### Database Constraints Added

Recent improvements (October 2025):

1. **NOT NULL constraints:**
   - `devices.user_id` now requires a user (prevents orphaned devices)

2. **Foreign keys:**
   - All major relationships have foreign keys with CASCADE or NULLIFY
   - See `db/schema.rb` for complete list

### Migration Best Practices

When writing migrations that delete or modify records:

**✅ Good:**
```ruby
class RemoveOldFeature < ActiveRecord::Migration[7.0]
  def up
    # Use ActiveRecord for deletions
    Goal.where(some_condition: true).destroy_all
  end
end
```

**❌ Bad:**
```ruby
class RemoveOldFeature < ActiveRecord::Migration[7.0]
  def up
    # Bypasses callbacks!
    execute "DELETE FROM goals WHERE some_condition = true"
  end
end
```

### Rails Console Safety

When cleaning up data in Rails console:

```ruby
# ✅ Safe
Goal.find(123).destroy
AgentTask.where(status: 'cancelled').destroy_all

# ❌ Dangerous
Goal.delete(123)  # Skips callbacks!
AgentTask.where(status: 'cancelled').delete_all  # Skips callbacks!
```

**Remember:** `.destroy` and `.destroy_all` trigger callbacks. `.delete` and `.delete_all` do not.

### Summary

- Always use ActiveRecord for deletions (`.destroy`, `.destroy_all`)
- Never use SQL DELETE on tables with polymorphic associations
- Database-level cascades protect most relationships
- Polymorphic associations require application-level cleanup

---

**Last updated:** October 29, 2025
