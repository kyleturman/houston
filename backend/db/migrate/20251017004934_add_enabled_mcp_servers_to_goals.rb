class AddEnabledMcpServersToGoals < ActiveRecord::Migration[8.0]
  def change
    add_column :goals, :enabled_mcp_servers, :text, comment: 'JSON array of enabled MCP server names for this goal'
  end
end
