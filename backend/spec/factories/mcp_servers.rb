FactoryBot.define do
  factory :mcp_server do
    sequence(:name) { |n| "test-mcp-server-#{n}" }
    transport { 'stdio' }
    endpoint { 'stdio' }
    healthy { true }
    tools_cache { [] }
    metadata { { 'kind' => 'local' } }
  end
end
