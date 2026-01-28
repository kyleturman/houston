class MigratePlaidConnectionsToUserMcpConnections < ActiveRecord::Migration[8.0]
  def up
    # Find or create Plaid MCP server record
    plaid_server = McpServer.find_or_create_by!(name: 'plaid') do |server|
      server.transport = 'stdio'
      server.endpoint = 'stdio'
      server.healthy = true
      server.metadata = {
        'auth_provider' => 'auth-providers/plaid.json',
        'connectionStrategy' => 'multiple'
      }
    end

    # Migrate PlaidConnection records to UserMcpConnection
    if defined?(PlaidConnection) && PlaidConnection.table_exists?
      PlaidConnection.find_each do |plaid_conn|
        # Build credentials JSON
        credentials_json = {
          'accessToken' => plaid_conn.access_token,
          'itemId' => plaid_conn.item_id
        }.to_json

        # Build metadata
        metadata_hash = {
          'institution_name' => plaid_conn.institution_name,
          'institution_id' => plaid_conn.institution_id,
          'accounts' => plaid_conn.metadata&.dig('accounts') || []
        }

        # Create UserMcpConnection
        UserMcpConnection.create!(
          user_id: plaid_conn.user_id,
          mcp_server: plaid_server,
          connection_identifier: plaid_conn.item_id,
          credentials: credentials_json,
          metadata: metadata_hash,
          status: plaid_conn.status == 'active' ? 'active' : 'disconnected',
          created_at: plaid_conn.created_at,
          updated_at: plaid_conn.updated_at
        )
      rescue => e
        Rails.logger.error("Failed to migrate PlaidConnection #{plaid_conn.id}: #{e.message}")
        # Continue with other records
      end
    end
  end

  def down
    # Reverse migration would go here if needed
    # For now, we'll keep it simple and not reverse
  end
end
