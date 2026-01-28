# frozen_string_literal: true

# System status script - shows overview of system state
# Run via: make status

puts "📊 Houston Status\n\n"

# Database stats
puts "📦 Database:"
puts "   Users: #{User.count}"
puts "   Goals: #{Goal.count} (#{Goal.where(status: :working).count} working)"
puts "   Tasks: #{AgentTask.count} (#{AgentTask.where(status: :active).count} active)"
puts "   Notes: #{Note.count}"
puts ""

# MCP servers
puts "🔌 MCP Servers:"
McpServer.order(:name).each do |server|
  status = server.healthy? ? "✅" : "❌"
  tools = server.tools_cache&.size || 0
  puts "   #{status} #{server.name} (#{tools} tools)"
end
puts ""

# Connections
puts "🔗 User Connections:"
UserMcpConnection.group(:remote_server_name).count.each do |name, count|
  next if name.blank?
  puts "   #{name}: #{count} connection(s)"
end
local_conns = UserMcpConnection.where.not(mcp_server_id: nil).count
puts "   Local servers: #{local_conns} connection(s)" if local_conns > 0
puts ""

# Recent activity
puts "📈 Recent Activity (24h):"
puts "   Goals created: #{Goal.where('created_at > ?', 24.hours.ago).count}"
puts "   Tasks completed: #{AgentTask.where(status: :completed).where('updated_at > ?', 24.hours.ago).count}"
puts "   Messages: #{ThreadMessage.where('created_at > ?', 24.hours.ago).count}"
puts ""

puts "✅ System operational"
