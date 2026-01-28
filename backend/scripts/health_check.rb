# frozen_string_literal: true

# Production data health check script
# Run via: make health-check
# Or: docker-compose exec backend bundle exec rails runner scripts/health_check.rb
#
# This script validates production data integrity and catches issues like:
# - Corrupted encrypted fields
# - Orphaned records
# - Invalid state transitions
# - Missing required associations

class HealthCheck
  attr_reader :errors, :warnings

  def initialize
    @errors = []
    @warnings = []
  end

  def run!
    puts "🏥 Running production health checks...\n\n"

    check_mcp_connections
    check_goals
    check_users
    check_agent_tasks

    print_results
    exit(@errors.any? ? 1 : 0)
  end

  private

  def check_mcp_connections
    puts "📡 Checking MCP connections..."

    UserMcpConnection.find_each do |conn|
      # Check encrypted credentials can be decrypted
      begin
        conn.parsed_credentials
      rescue ActiveRecord::Encryption::Errors::Decryption => e
        @errors << "UserMcpConnection #{conn.id}: Corrupted credentials (decryption failed)"
      end

      # Check server_url can be accessed
      begin
        conn.server_url
      rescue => e
        @errors << "UserMcpConnection #{conn.id}: server_url error - #{e.class}"
      end

      # Check server_name is present for remote connections
      if conn.remote_server? && conn.server_name.blank?
        @warnings << "UserMcpConnection #{conn.id}: Remote connection missing server_name"
      end
    end

    puts "   ✓ Checked #{UserMcpConnection.count} connections"
  end

  def check_goals
    puts "🎯 Checking goals..."

    Goal.find_each do |goal|
      # Check llm_history is valid JSON array
      if goal.llm_history.present? && !goal.llm_history.is_a?(Array)
        @errors << "Goal #{goal.id}: llm_history is not an array"
      end

      # Check enabled_mcp_servers is valid
      if goal.enabled_mcp_servers.present? && !goal.enabled_mcp_servers.is_a?(Array)
        @errors << "Goal #{goal.id}: enabled_mcp_servers is not an array"
      end

      # Check for orphaned goals (missing user)
      unless goal.user
        @errors << "Goal #{goal.id}: Missing user association"
      end
    end

    puts "   ✓ Checked #{Goal.count} goals"
  end

  def check_users
    puts "👤 Checking users..."

    User.find_each do |user|
      # Check user has valid user_agent
      unless user.user_agent
        @warnings << "User #{user.id} (#{user.email}): Missing user_agent"
      end
    end

    puts "   ✓ Checked #{User.count} users"
  end

  def check_agent_tasks
    puts "📋 Checking agent tasks..."

    AgentTask.find_each do |task|
      # Check for orphaned tasks
      if task.taskable_type == 'Goal' && task.taskable.nil?
        @errors << "AgentTask #{task.id}: Orphaned task (missing goal)"
      end

      if task.taskable_type == 'UserAgent' && task.taskable.nil?
        @errors << "AgentTask #{task.id}: Orphaned task (missing user_agent)"
      end

      # Check llm_history is valid
      if task.llm_history.present? && !task.llm_history.is_a?(Array)
        @errors << "AgentTask #{task.id}: llm_history is not an array"
      end
    end

    puts "   ✓ Checked #{AgentTask.count} tasks"
  end

  def print_results
    puts "\n" + "=" * 50

    if @errors.empty? && @warnings.empty?
      puts "✅ All health checks passed!"
      return
    end

    if @errors.any?
      puts "\n❌ ERRORS (#{@errors.count}):"
      @errors.each { |e| puts "   • #{e}" }
    end

    if @warnings.any?
      puts "\n⚠️  WARNINGS (#{@warnings.count}):"
      @warnings.each { |w| puts "   • #{w}" }
    end

    puts "\n" + "=" * 50
  end
end

HealthCheck.new.run!
