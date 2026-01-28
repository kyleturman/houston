# frozen_string_literal: true

class SimplifyAgentActivityLogs < ActiveRecord::Migration[7.1]
  def change
    if column_exists?(:agent_activity_logs, :event_type)
      remove_column :agent_activity_logs, :event_type, :string
    end
    if column_exists?(:agent_activity_logs, :tokens_in)
      remove_column :agent_activity_logs, :tokens_in, :integer
    end
    if column_exists?(:agent_activity_logs, :tokens_out)
      remove_column :agent_activity_logs, :tokens_out, :integer
    end
  end
end
