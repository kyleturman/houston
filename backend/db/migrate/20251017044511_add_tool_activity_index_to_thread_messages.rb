class AddToolActivityIndexToThreadMessages < ActiveRecord::Migration[8.0]
  def change
    # Add GIN index for JSONB queries on metadata -> 'tool_activity' -> 'id'
    # This optimizes the queries we added to find ThreadMessages by activity_id
    add_index :thread_messages, 
              "(metadata -> 'tool_activity')", 
              using: :gin, 
              name: 'index_thread_messages_on_tool_activity'
    
    # Add GIN index for JSONB queries on metadata -> 'tool_activity' -> 'task_id'
    # This optimizes the query in AgentTask#update_task_thread_message_status
    add_index :thread_messages,
              "((metadata -> 'tool_activity' ->> 'task_id'))",
              name: 'index_thread_messages_on_tool_activity_task_id'
  end
end
