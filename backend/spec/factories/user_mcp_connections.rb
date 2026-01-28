FactoryBot.define do
  factory :user_mcp_connection do
    association :user
    association :mcp_server # For local MCP servers
    credentials { { access_token: 'sample_access_token' }.to_json }
    connection_identifier { "conn_#{SecureRandom.hex(4)}" }
    metadata { {} }
    status { 'active' }

    # Trait for remote server connections using remote_server_config model
    trait :remote_with_config do
      transient do
        server_name { 'test-server' }
        server_display_name { nil }
      end

      mcp_server { nil }
      remote_mcp_server { nil }
      remote_server_name { server_name }
      credentials { { 'access_token' => 'sample_access_token' }.to_json }
      metadata do
        {
          'remote_server_config' => {
            'name' => server_name,
            'display_name' => server_display_name || server_name.titleize,
            'url' => 'https://mcp.example.com/api',
            'auth_type' => 'oauth_consent',
            'source' => 'default'
          }
        }
      end
    end

    # Trait for direct URL server connections (no OAuth) using new model
    trait :direct_with_config do
      mcp_server { nil }
      remote_mcp_server { nil }
      remote_server_name { 'user-added-server' }
      credentials { { 'url' => 'https://mcp.example.com/api' }.to_json }
      metadata do
        {
          'remote_server_config' => {
            'name' => 'user-added-server',
            'display_name' => 'User Added Server',
            'auth_type' => 'direct',
            'source' => 'user_added'
          }
        }
      end
    end

    # Trait for user-added server connections
    trait :user_added do
      mcp_server { nil }
      remote_mcp_server { nil }
      remote_server_name { 'custom-server' }
      credentials { { 'url' => 'https://custom.mcp.example.com/api' }.to_json }
      metadata do
        {
          'remote_server_config' => {
            'name' => 'custom-server',
            'display_name' => 'Custom Server',
            'auth_type' => 'direct',
            'source' => 'user_added'
          }
        }
      end
    end

    # Trait for multi-account remote server (e.g., multiple Notion workspaces)
    trait :with_workspace do
      transient do
        server_name { 'notion' }
        workspace_id { SecureRandom.uuid }
        workspace_name { 'My Workspace' }
      end

      mcp_server { nil }
      remote_mcp_server { nil }
      remote_server_name { server_name }
      connection_identifier { workspace_id }
      metadata do
        {
          'remote_server_config' => {
            'name' => server_name,
            'display_name' => server_name.titleize,
            'url' => 'https://api.notion.com/mcp',
            'auth_type' => 'oauth_consent',
            'source' => 'default'
          },
          'workspace_id' => workspace_id,
          'workspace_name' => workspace_name
        }
      end
    end

    # LEGACY traits for backward compatibility during migration
    # These will be removed after migration is complete

    # Trait for remote OAuth server connections (legacy)
    trait :remote do
      mcp_server { nil }
      association :remote_mcp_server
    end

    # Trait for direct URL server connections (legacy)
    trait :direct do
      mcp_server { nil }
      association :remote_mcp_server, :direct
      credentials { { 'url' => 'https://mcp.example.com/api' }.to_json }
    end
  end
end
