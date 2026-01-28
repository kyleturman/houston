class FixEnabledMcpServersPrefix < ActiveRecord::Migration[7.1]
  def up
    # Fix goals with "local_" prefix in enabled_mcp_servers
    Goal.where.not(enabled_mcp_servers: [nil, []]).find_each do |goal|
      servers = goal.enabled_mcp_servers
      next if servers.blank?

      # Strip "local_" prefix from each server name
      fixed_servers = servers.map do |server|
        server.sub(/^local_/, '')
      end

      # Only update if something changed
      if fixed_servers != servers
        goal.update_column(:enabled_mcp_servers, fixed_servers)
        puts "Fixed goal #{goal.id} (#{goal.title}): #{servers.inspect} -> #{fixed_servers.inspect}"
      end
    end
  end

  def down
    # No-op: we don't want to re-add the prefix
  end
end
