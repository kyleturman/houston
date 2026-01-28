# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_01_28_003302) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_activities", force: :cascade do |t|
    t.string "agentable_type", null: false
    t.bigint "agentable_id", null: false
    t.bigint "goal_id"
    t.string "agent_type", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cost_cents", default: 0, null: false
    t.jsonb "tools_called", default: [], null: false
    t.integer "tool_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at", null: false
    t.integer "iterations", default: 1, null: false
    t.boolean "natural_completion", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type", "completed_at"], name: "index_agent_activities_on_agent_type_and_completed_at"
    t.index ["agent_type"], name: "index_agent_activities_on_agent_type"
    t.index ["agentable_type", "agentable_id", "completed_at"], name: "idx_on_agentable_type_agentable_id_completed_at_694d64f5f5"
    t.index ["agentable_type", "agentable_id"], name: "index_agent_activities_on_agentable"
    t.index ["completed_at"], name: "index_agent_activities_on_completed_at"
    t.index ["goal_id", "completed_at"], name: "index_agent_activities_on_goal_id_and_completed_at"
    t.index ["goal_id"], name: "index_agent_activities_on_goal_id"
    t.index ["started_at"], name: "index_agent_activities_on_started_at"
  end

  create_table "agent_histories", force: :cascade do |t|
    t.string "agentable_type", null: false
    t.bigint "agentable_id", null: false
    t.jsonb "agent_history", default: [], null: false
    t.text "summary", null: false
    t.string "completion_reason"
    t.integer "message_count"
    t.integer "token_count"
    t.datetime "started_at"
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agentable_type", "agentable_id", "completed_at"], name: "index_agent_histories_on_agentable_and_date"
    t.index ["agentable_type", "agentable_id"], name: "index_agent_histories_on_agentable"
    t.index ["completed_at"], name: "index_agent_histories_on_completed_at"
  end

  create_table "agent_tasks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "goal_id"
    t.bigint "parent_task_id"
    t.string "title", null: false
    t.text "instructions"
    t.integer "status", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.string "blocking_reason"
    t.jsonb "context_data", default: {}, null: false
    t.string "agent_job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "orchestrator_job_id"
    t.jsonb "orchestrator_state", default: {}, null: false
    t.jsonb "result_data", default: {}, null: false
    t.text "result_summary"
    t.string "error_type"
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.datetime "next_retry_at", precision: nil
    t.string "cancelled_reason"
    t.jsonb "runtime_state", default: {}, null: false
    t.jsonb "llm_history", default: [], null: false
    t.string "taskable_type"
    t.bigint "taskable_id"
    t.string "origin_tool_activity_id"
    t.index ["agent_job_id"], name: "index_agent_tasks_on_agent_job_id"
    t.index ["goal_id"], name: "index_agent_tasks_on_goal_id"
    t.index ["orchestrator_job_id"], name: "index_agent_tasks_on_orchestrator_job_id"
    t.index ["origin_tool_activity_id"], name: "index_agent_tasks_on_origin_tool_activity_id"
    t.index ["parent_task_id"], name: "index_agent_tasks_on_parent_task_id"
    t.index ["priority"], name: "index_agent_tasks_on_priority"
    t.index ["status"], name: "index_agent_tasks_on_status"
    t.index ["taskable_type", "taskable_id"], name: "index_agent_tasks_on_taskable_type_and_taskable_id"
    t.index ["user_id", "status"], name: "index_agent_tasks_on_user_id_and_status"
    t.index ["user_id"], name: "index_agent_tasks_on_user_id"
  end

  create_table "devices", force: :cascade do |t|
    t.string "name", null: false
    t.string "platform", null: false
    t.string "token_digest", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token_id", null: false
    t.bigint "user_id", null: false
    t.datetime "last_used_at"
    t.index ["created_at"], name: "index_devices_on_created_at"
    t.index ["platform"], name: "index_devices_on_platform"
    t.index ["token_id"], name: "index_devices_on_token_id", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "feed_insights", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "user_agent_id", null: false
    t.integer "insight_type", default: 0, null: false
    t.integer "goal_ids", default: [], array: true
    t.text "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "display_order", default: 0, null: false
    t.string "time_period"
    t.index ["created_at"], name: "index_feed_insights_on_created_at"
    t.index ["display_order"], name: "index_feed_insights_on_display_order"
    t.index ["insight_type"], name: "index_feed_insights_on_insight_type"
    t.index ["user_agent_id"], name: "index_feed_insights_on_user_agent_id"
    t.index ["user_id", "created_at"], name: "index_feed_insights_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_feed_insights_on_user_id"
  end

  create_table "goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "agent_instructions"
    t.string "agent_job_id"
    t.jsonb "runtime_state", default: {}, null: false
    t.datetime "last_agent_run"
    t.datetime "last_proactive_check_at"
    t.jsonb "llm_history", default: [], null: false
    t.jsonb "learnings", default: [], null: false
    t.string "accent_color"
    t.text "enabled_mcp_servers", comment: "JSON array of enabled MCP server names for this goal"
    t.integer "display_order", default: 0, null: false
    t.jsonb "check_in_schedule"
    t.index ["agent_job_id"], name: "index_goals_on_agent_job_id"
    t.index ["last_proactive_check_at"], name: "index_goals_on_last_proactive_check_at"
    t.index ["status"], name: "index_goals_on_status"
    t.index ["user_id", "display_order"], name: "index_goals_on_user_id_and_display_order"
    t.index ["user_id", "status"], name: "index_goals_on_user_id_and_status"
    t.index ["user_id"], name: "index_goals_on_user_id"
  end

  create_table "invite_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at"
    t.datetime "first_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_invite_tokens_on_expires_at"
    t.index ["first_used_at"], name: "index_invite_tokens_on_first_used_at"
    t.index ["user_id"], name: "index_invite_tokens_on_user_id"
  end

  create_table "llm_costs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "agentable_type"
    t.bigint "agentable_id"
    t.string "provider", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.decimal "cost", precision: 10, scale: 6, default: "0.0", null: false
    t.string "context"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cache_creation_input_tokens", default: 0, null: false
    t.integer "cache_read_input_tokens", default: 0, null: false
    t.integer "cached_tokens", default: 0, null: false
    t.index ["agentable_type", "agentable_id"], name: "index_llm_costs_on_agentable"
    t.index ["user_id", "created_at"], name: "index_llm_costs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_llm_costs_on_user_id"
  end

  create_table "mcp_servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "transport", default: "http", null: false
    t.string "endpoint"
    t.string "command"
    t.boolean "healthy", default: false, null: false
    t.datetime "last_seen_at"
    t.jsonb "tools_cache", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_mcp_servers_on_name", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "goal_id"
    t.text "content"
    t.jsonb "metadata", default: {}, null: false
    t.integer "source", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "title"
    t.integer "display_order"
    t.index ["display_order"], name: "index_notes_on_display_order"
    t.index ["goal_id"], name: "index_notes_on_goal_id"
    t.index ["source"], name: "index_notes_on_source"
    t.index ["user_id", "goal_id"], name: "index_notes_on_user_id_and_goal_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "remote_mcp_servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "url"
    t.string "auth_type", default: "none"
    t.boolean "default_enabled", default: false
    t.text "description"
    t.json "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_remote_mcp_servers_on_name", unique: true
  end

  create_table "thread_messages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "source", default: 0, null: false
    t.text "content", null: false
    t.jsonb "metadata", default: {}, null: false
    t.boolean "processed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_type", default: 0, null: false
    t.string "agentable_type", null: false
    t.bigint "agentable_id", null: false
    t.string "tool_activity_id"
    t.bigint "agent_history_id"
    t.index "(((metadata -> 'tool_activity'::text) ->> 'task_id'::text))", name: "index_thread_messages_on_tool_activity_task_id"
    t.index "((metadata -> 'tool_activity'::text))", name: "index_thread_messages_on_tool_activity", using: :gin
    t.index ["agent_history_id"], name: "index_thread_messages_on_agent_history_id"
    t.index ["agentable_type", "agentable_id"], name: "index_thread_messages_on_agentable_type_and_agentable_id"
    t.index ["message_type"], name: "index_thread_messages_on_message_type"
    t.index ["tool_activity_id"], name: "index_thread_messages_on_tool_activity_id"
    t.index ["user_id"], name: "index_thread_messages_on_user_id"
  end

  create_table "user_agents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "llm_history", default: [], null: false
    t.jsonb "learnings", default: [], null: false
    t.jsonb "runtime_state", default: {}, null: false
    t.datetime "last_synthesis_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_synthesis_at"], name: "index_user_agents_on_last_synthesis_at"
    t.index ["user_id"], name: "index_user_agents_on_user_id", unique: true
  end

  create_table "user_mcp_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "remote_mcp_server_id"
    t.text "credentials"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.json "metadata", default: {}
    t.string "status", default: "active"
    t.string "code_verifier"
    t.string "state"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "mcp_server_id"
    t.string "connection_identifier"
    t.string "remote_server_name"
    t.index ["mcp_server_id", "status"], name: "index_user_mcp_connections_on_mcp_server_id_and_status"
    t.index ["mcp_server_id"], name: "index_user_mcp_connections_on_mcp_server_id"
    t.index ["remote_mcp_server_id"], name: "index_user_mcp_connections_on_remote_mcp_server_id"
    t.index ["remote_server_name"], name: "idx_remote_server_name", where: "(remote_server_name IS NOT NULL)"
    t.index ["user_id", "mcp_server_id", "connection_identifier"], name: "idx_user_server_connection", unique: true
    t.index ["user_id", "remote_mcp_server_id"], name: "index_user_mcp_connections_unique", unique: true
    t.index ["user_id", "remote_server_name", "connection_identifier"], name: "idx_user_remote_server_connection", unique: true, where: "(remote_server_name IS NOT NULL)"
    t.index ["user_id"], name: "index_user_mcp_connections_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "total_llm_cost", precision: 10, scale: 6, default: "0.0", null: false
    t.string "name"
    t.boolean "onboarding_completed", default: false, null: false
    t.string "role", default: "user", null: false
    t.boolean "active", default: true, null: false
    t.index ["active"], name: "index_users_on_active"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "agent_activities", "goals"
  add_foreign_key "agent_tasks", "agent_tasks", column: "parent_task_id"
  add_foreign_key "agent_tasks", "goals"
  add_foreign_key "agent_tasks", "users"
  add_foreign_key "devices", "users"
  add_foreign_key "feed_insights", "user_agents"
  add_foreign_key "feed_insights", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "invite_tokens", "users"
  add_foreign_key "llm_costs", "users"
  add_foreign_key "notes", "goals"
  add_foreign_key "notes", "users"
  add_foreign_key "thread_messages", "agent_histories", on_delete: :cascade
  add_foreign_key "thread_messages", "users"
  add_foreign_key "user_agents", "users"
  add_foreign_key "user_mcp_connections", "mcp_servers"
  add_foreign_key "user_mcp_connections", "remote_mcp_servers"
  add_foreign_key "user_mcp_connections", "users"
end
