class MakeAgentInstanceIdNullableInThreadMessages < ActiveRecord::Migration[8.0]
  def change
    # Make agent_instance_id nullable in thread_messages for transition to polymorphic agentable
    change_column_null :thread_messages, :agent_instance_id, true
    
    # Also make it nullable in agent_activity_logs
    change_column_null :agent_activity_logs, :agent_instance_id, true
  end
end
