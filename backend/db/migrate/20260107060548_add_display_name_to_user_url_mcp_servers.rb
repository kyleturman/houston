class AddDisplayNameToUserUrlMcpServers < ActiveRecord::Migration[8.0]
  def change
    add_column :user_url_mcp_servers, :display_name, :string
  end
end
