# frozen_string_literal: true

module Tools
  # Registry: system tools locally + MCP tools via connection manager
  class Registry
    # Auto-discover all system tools from app/services/tools/system/
    # Excludes BaseTool. Tools are registered by their metadata name.
    SYSTEM_TOOLS = begin
      tools_dir = Rails.root.join('app', 'services', 'tools', 'system')
      tool_files = Dir.glob(tools_dir.join('*.rb'))

      tool_files.each_with_object({}) do |file, hash|
        # Skip base_tool.rb
        next if file.end_with?('base_tool.rb')

        # Convert file path to class name: create_note.rb -> CreateNote
        class_name = File.basename(file, '.rb').camelize
        full_class_name = "Tools::System::#{class_name}"

        begin
          # Require and constantize the class
          require_dependency file unless Rails.env.production?
          klass = full_class_name.constantize

          # Get tool name from metadata
          tool_name = klass.metadata[:name]
          hash[tool_name] = full_class_name
        rescue NameError => e
          Rails.logger.warn("[Registry] Could not load tool class #{full_class_name}: #{e.message}")
        end
      end
    end.freeze

    def enabled_tools_for_context(context)
      case context
      when :goal
        # Goals have access to all system tools except generate_feed_insights (user_agent only)
        # search_notes and search_agent_history are conditionally available
        # emit_task_progress is task-only (for task activity status display)
        tools = SYSTEM_TOOLS.keys - ['generate_feed_insights', 'search_agent_history', 'emit_task_progress']

        # Dynamic search_notes availability based on note count
        goal = @goal || (@agentable.is_a?(Goal) ? @agentable : nil)
        if goal && !goal.requires_search_tool?
          tools = tools - ['search_notes']
        end

        # Add search_agent_history if this goal has conversation history
        if @agentable.respond_to?(:agent_histories) && @agentable.agent_histories.exists?
          tools = tools + ['search_agent_history']
        end

        tools
      when :task
        # Check if this is a standalone task (no goal) or goal task
        task = @task || (@agentable.is_a?(AgentTask) ? @agentable : nil)
        is_standalone = task && task.goal.nil?

        if is_standalone
          # Standalone tasks (created by UserAgent) need generate_feed_insights
          # They don't need goal-specific tools
          SYSTEM_TOOLS.keys - ['create_task', 'search_notes', 'search_agent_history', 'manage_check_in', 'save_learning', 'manage_learning']
        else
          # Goal tasks: can't create other tasks, generate feed insights, or search notes
          # Tasks receive full context via creation prompt - no search needed
          # Tasks don't have agent_history (short-lived)
          SYSTEM_TOOLS.keys - ['create_task', 'generate_feed_insights', 'search_notes', 'search_agent_history', 'manage_check_in']
        end
      when :user_agent
        # UserAgent only needs minimal system tools (MCP tools like brave_web_search added separately)
        # UserAgent doesn't need check-ins (runs on schedule)
        tools = ['send_message', 'manage_learning', 'search_notes', 'generate_feed_insights', 'create_task']

        # Add search_agent_history if this user_agent has conversation history
        if @agentable.respond_to?(:agent_histories) && @agentable.agent_histories.exists?
          tools = tools + ['search_agent_history']
        end

        tools
      else
        # Default: all tools available
        SYSTEM_TOOLS.keys
      end
    end

    def system_tool_schema(name)
      # Dynamically load schema from the tool class
      tool_class = find_tool_class(name.to_s)
      return tool_class.schema if tool_class.respond_to?(:schema)

      # Fallback for tools that don't define schema (backward compatibility)
      { type: 'object', additionalProperties: true }
    end

    def initialize(user:, goal: nil, task: nil, agentable:, mcp_manager: nil, context: nil)
      @user = user
      @goal = goal
      @task = task
      @agentable = agentable
      @mcp_manager = mcp_manager || Mcp::ConnectionManager.instance
      @context = context || {}
    end

    # (removed legacy call implementation that logged AgentActivityLog)

    # Backward-compatible: list tools with optional restricted names
    def available_tools(restricted: [])
      sys = system_available_tools(restricted: restricted)
      mcp = @mcp_manager.list_tools.map do |t|
        # Normalize keys (DB stores string keys)
        t_name = Utils::HashAccessor.hash_get(t, :name)
        t_desc = Utils::HashAccessor.hash_get(t, :description)
        t_hint = Utils::HashAccessor.hash_get(t, :params_hint)
        next if restricted&.include?(t_name)
        { name: t_name, description: t_desc, params_hint: t_hint }
      end.compact
      sys + mcp
    end

    # Provider-ready tools including JSON Schema when available.
    # context: :goal, :task, or :user_agent. Applies context-specific tool access.
    def provider_tools(context: nil)
      enabled = enabled_tools_for_context(context)
      # System tools with schemas (only enabled ones)
      sys = system_available_tools(restricted: []).select { |meta| enabled.include?(meta[:name]) }.map do |meta|
        schema = system_tool_schema(meta[:name])
        { name: meta[:name], description: meta[:description], input_schema: schema }
      end

      # MCP tools filtered by enabled_mcp_servers
      # Default MCP servers for all goals/tasks/user_agent: brave-search (web search)
      enabled_mcp_servers = if @goal&.enabled_mcp_servers.present?
        @goal.enabled_mcp_servers.map(&:downcase)  # Normalize to lowercase for comparison
      else
        ['brave-search'] # Default: web search available to all contexts (goals, tasks, user_agent)
      end

      mcp = @mcp_manager.list_tools.select do |t|
        tool_name = Utils::HashAccessor.hash_get(t, :name)
        # Get the actual server name from MCP manager instead of inferring
        server_name = @mcp_manager.server_name_for_tool(tool_name)
        enabled_mcp_servers.include?(server_name&.downcase)  # Case-insensitive comparison
      end.map do |t|
        # Normalize keys
        t_name = Utils::HashAccessor.hash_get(t, :name)
        t_desc = Utils::HashAccessor.hash_get(t, :description)
        meta = @mcp_manager.tool_metadata(t_name) || {}
        schema = Utils::HashAccessor.hash_get(meta, :input_schema) ||
                 Utils::HashAccessor.hash_get(meta, :schema) ||
                 { type: 'object', additionalProperties: true }
        { name: t_name, description: t_desc, input_schema: schema }
      end.compact

      sys + mcp
    end

    def metadata_for(name)
      system_metadata_for(name) || @mcp_manager.tool_metadata(name.to_s)
    end

    # Find tool class by name (public method for CoreLoop)
    def find_tool_class(name)
      if SYSTEM_TOOLS.key?(name.to_s)
        tool_class_name = SYSTEM_TOOLS[name.to_s]
        return tool_class_name.constantize
      end
      nil
    end

    def call(name, activity_id: nil, **params)
      # Handle INVALID_JSON from streaming tool parsing failures
      if params.key?('INVALID_JSON') || params.key?(:INVALID_JSON)
        invalid_json = params['INVALID_JSON'] || params[:INVALID_JSON]
        Rails.logger.warn("[ToolRegistry] Received INVALID_JSON for #{name}: #{invalid_json[0..200]}...")
        
        # Try to repair the JSON and extract proper parameters
        begin
          # Remove the INVALID_JSON wrapper and try to parse the content
          repaired_params = JSON.parse(invalid_json)
          Rails.logger.info("[ToolRegistry] Successfully repaired INVALID_JSON for #{name}")
          # Convert to symbol keys for Ruby keyword arguments
          params = repaired_params.with_indifferent_access.symbolize_keys
        rescue JSON::ParserError => e
          Rails.logger.error("[ToolRegistry] Could not repair INVALID_JSON for #{name}: #{e.message}")
          return {
            success: false,
            error: "Tool call failed due to malformed JSON parameters",
            observation: "The tool call failed because the parameters were not properly formatted. Please try again with correct parameters."
          }
        end
      end

      # Try system tools first
      if SYSTEM_TOOLS.key?(name.to_s)
        tool_class_name = SYSTEM_TOOLS[name.to_s]
        tool_class = tool_class_name.constantize
        tool_instance = tool_class.new(user: @user, goal: @goal, task: @task, agentable: @agentable, activity_id: activity_id, context: @context)
        result = tool_instance.safe_execute(**params)

        # Create consistent ThreadMessage for user-facing tools only
        # (send_message creates its own agent messages, internal tools don't need ThreadMessages)
        tool_metadata = tool_class.metadata
        is_user_facing = tool_metadata.fetch(:is_user_facing, true)
        if name.to_s != 'send_message' && is_user_facing
          create_tool_thread_message(name.to_s, params, result, activity_id)
        end

        return result
      end

      # Try MCP tools if system tool not found
      if @mcp_manager.has_tool?(name.to_s)
        result = @mcp_manager.call_tool(name.to_s, user: @user, **params)

        Rails.logger.warn("[Registry] MCP tool '#{name}' returned: #{result.inspect[0..500]}")

        # Sanitize MCP errors to prevent massive stack traces in LLM context
        if result.is_a?(Hash) && result['isError'] && result['content'].is_a?(String)
          if result['content'].length > 500
            result['content'] = result['content'].truncate(500)
          end
        end

        # Create consistent ThreadMessage for all tools
        create_tool_thread_message(name.to_s, params, result, activity_id)

        # Enhance MCP tool results with rich observations for ReAct pattern
        enhanced_result = enhance_mcp_result(name.to_s, params, result)

        Rails.logger.warn("[Registry] Enhanced result for '#{name}': #{enhanced_result.inspect[0..300]}")

        return enhanced_result
      end

      { success: false, error: "Tool '#{name}' not found" }
    end

    # Create ThreadMessage when tool starts (in progress state) - PUBLIC method
    def create_tool_start_message(tool_name:, params:, activity_id:)
      # Skip creating start message for non-user-facing tools (internal operations)
      if SYSTEM_TOOLS.key?(tool_name.to_s)
        tool_class = SYSTEM_TOOLS[tool_name.to_s].constantize
        tool_metadata = tool_class.metadata
        is_user_facing = tool_metadata.fetch(:is_user_facing, true)
        return unless is_user_facing
      end
      # MCP tools default to user-facing

      # Try to find an existing message for this activity (avoid duplicates when streaming)
      existing_message = ThreadMessage.where(
        user: @user,
        agentable: @agentable,
        source: :agent,
        message_type: :tool,
        tool_activity_id: activity_id
      ).first

      if existing_message
        # Update existing message to ensure correct name/status and merge any input params
        updates = {
          id: activity_id,
          name: existing_message.metadata.dig('tool_activity', 'name') || tool_name,
          status: 'in_progress'
        }

        if params.present?
          current_input = existing_message.metadata.dig('tool_activity', 'input') || {}
          updates[:input] = current_input.merge(params)
        end

        existing_message.update_tool_activity(updates)
        return existing_message
      end

      # Check if this might be a retry of a recently failed tool call
      # Look for the most recent failed message with the same tool name (within last 5 minutes)
      potential_retry_message = ThreadMessage.where(
        user: @user,
        agentable: @agentable,
        source: :agent,
        message_type: :tool
      ).where("metadata -> 'tool_activity' ->> 'name' = ?", tool_name)
       .where("metadata -> 'tool_activity' ->> 'status' = ?", 'failure')
       .where("created_at > ?", 5.minutes.ago)
       .order(created_at: :desc)
       .first

      if potential_retry_message
        # This looks like a retry! Reuse the existing message
        Rails.logger.info("[Registry] Detected retry for tool '#{tool_name}', reusing ThreadMessage #{potential_retry_message.id}")

        # Build retry metadata
        old_retry_count = potential_retry_message.metadata.dig('tool_activity', 'retry_count') || 0
        old_retry_history = potential_retry_message.metadata.dig('tool_activity', 'retry_history') || []
        old_error = potential_retry_message.metadata.dig('tool_activity', 'error')

        new_retry_count = old_retry_count + 1
        updated_history = old_retry_history + [{
          attempt: new_retry_count,
          timestamp: Time.current.iso8601,
          previous_error: old_error
        }]

        # Update with new activity_id and mark as retry
        potential_retry_message.update_tool_activity({
          id: activity_id,
          name: tool_name,
          status: 'in_progress',
          input: params,
          retry_count: new_retry_count,
          retry_history: updated_history
        })
        return potential_retry_message
      end

      # Build initial tool activity metadata for in-progress state
      tool_activity = {
        id: activity_id,
        name: tool_name,
        status: 'in_progress',
        input: params,
        display_message: friendly_tool_message(tool_name)
      }

      # Create ThreadMessage with in-progress tool activity
      # Client will render tool cell in loading state based on status: 'in_progress'
      ThreadMessage.create!(
        user: @user,
        agentable: @agentable,
        source: :agent,
        message_type: :tool,
        tool_activity_id: activity_id, # Indexed for efficient queries
        content: "Tool started: #{tool_name}",
        metadata: {
          tool_activity: tool_activity
        }
      )
    rescue => e
      Rails.logger.error("[Registry] Failed to create tool start message: #{e.message}")
    end

    # Update tool input/details while still in progress (used by streaming tool_complete from LLM)
    def update_tool_input_message(activity_id:, tool_name:, params: {})
      begin
        msg = ThreadMessage.where(
          user: @user,
          agentable: @agentable,
          source: :agent,
          message_type: :tool,
          tool_activity_id: activity_id
        ).first

        # If we can't find a message yet (race), create one now
        unless msg
          return create_tool_start_message(tool_name: tool_name, params: params || {}, activity_id: activity_id)
        end

        updates = {
          id: activity_id,
          name: msg.metadata.dig('tool_activity', 'name') || tool_name,
          status: 'in_progress'
        }

        if params.present?
          current_input = msg.metadata.dig('tool_activity', 'input') || {}
          updates[:input] = current_input.merge(params)
        end

        msg.update_tool_activity(updates)
      rescue => e
        Rails.logger.error("[Registry] Failed to update tool input message: #{e.message}")
      end
    end

    private

    # Determine tool status from result (works for both MCP and system tools)
    def determine_tool_status(result)
      # Handle explicit error indicators (from MCP error responses) FIRST
      # This check must come before content parsing because MCP tools return isError
      # flag alongside content, and content may not have a success field
      if result.key?(:isError) || result.key?("isError")
        is_error = result[:isError] || result["isError"]
        return is_error ? 'failure' : 'success'
      end

      # Handle MCP tool results (from ConnectionManager)
      # MCP tools return { content: [{ type: 'text', text: '{"events": [...], ...}' }] }
      if result.is_a?(Hash) && result['content'].is_a?(Array) && result['content'].first.is_a?(Hash)
        content_text = result['content'].first['text'] || result['content'].first[:text]

        if content_text.is_a?(String)
          begin
            # Parse the JSON inside the text field
            parsed = JSON.parse(content_text)
            # Check for explicit error indicator in parsed JSON
            if parsed['error'].present? || parsed[:error].present?
              return 'failure'
            end
            # Check for explicit success indicator, otherwise treat valid JSON as success
            # MCP tools often return data directly (e.g., {events: [...]}) without a success flag
            return 'success'
          rescue JSON::ParserError
            # If not JSON, treat non-error text as success
            return 'success'
          end
        end
      end

      # Handle error field
      if result.key?(:error) || result.key?("error")
        return 'failure'
      end

      # Handle system tools (standard format: { success: true, ... })
      if result[:success] == true || result["success"] == true
        return 'success'
      end

      # If we have a result with data but no explicit success/error, treat as success
      # (This handles tools that return data without a success flag)
      if result.is_a?(Hash) && result.keys.any? && !result.key?(:error) && !result.key?("error")
        return 'success'
      end

      # Default to failure if we can't determine status
      'failure'
    end

    # Add result data to tool_activity (excluding internal keys)
    # Standardized: all tool result data goes in tool_activity.data
    # Also adds normalized_results for consistent iOS display
    def add_result_data_to_activity(tool_activity, result)
      excluded_keys = [:success, :error, :error_class, :observation]
      data = {}
      result.each do |key, value|
        next if excluded_keys.include?(key)
        next if value.nil?
        data[key] = value
      end

      # Add normalized results for iOS to display consistently
      if data.present?
        normalized = normalize_mcp_results_for_display(data)
        data['normalized_results'] = normalized if normalized.present?
      end

      tool_activity['data'] = data if data.present?
    end

    # Normalize MCP results into a consistent format for iOS display
    # Returns array of {title, url, description} hashes
    def normalize_mcp_results_for_display(data)
      return nil unless data.is_a?(Hash)

      # Try to find the result content
      content_text = nil
      if data['content'].is_a?(Array) && data['content'].first.is_a?(Hash)
        content_text = data['content'].first['text']
      elsif data[:result].is_a?(String)
        content_text = data[:result]
      end

      return nil unless content_text.is_a?(String)

      begin
        parsed = JSON.parse(content_text)
        extract_normalized_items(parsed)
      rescue JSON::ParserError
        nil
      end
    end

    # Extract items from parsed JSON and normalize to {title, url, description}
    def extract_normalized_items(data)
      return nil unless data.is_a?(Hash)

      # Find the items - could be an array or a single object
      items = nil
      result_keys = %w[results items data records entries events messages tasks notes pages tracks albums artists playlists]

      result_keys.each do |key|
        value = data[key]
        if value.is_a?(Array) && value.any?
          items = value
          break
        elsif value.is_a?(Hash) && value.keys.any?
          # Single result object (e.g., Zapier's filtered output)
          items = [value]
          break
        end
      end

      # If no nested results found, treat the whole data as a single result
      if items.nil? && data.keys.any? { |k| %w[name title subject album_name track_name].include?(k) }
        items = [data]
      end

      return nil unless items.is_a?(Array) && items.any?

      # Normalize each item
      items.first(20).filter_map do |item|
        next unless item.is_a?(Hash)
        normalize_single_item(item)
      end
    end

    # Normalize a single item to {title, url, description}
    def normalize_single_item(item)
      return nil unless item.is_a?(Hash)

      # Extract title from common fields (including Zapier-style album_name, track_name)
      title = find_first_string(item, %w[name title subject summary label display_name headline filename album_name track_name playlist_name artist_name song_name event_name])

      # Build subtitle from secondary info (artist, author, type, etc.)
      subtitle_parts = []

      # Artist/author
      artist = item.dig('artists', 0, 'name') || item['artist'] || item['author'] || item['creator']
      subtitle_parts << artist if artist.is_a?(String)

      # Type/category
      type = item['type'] || item['kind'] || item['category']
      subtitle_parts << type.to_s.capitalize if type.is_a?(String) && subtitle_parts.empty?

      # Extract URL from common fields
      url = find_first_url(item)

      # Extract description
      description = find_first_string(item, %w[description snippet summary text body content abstract])

      # Use subtitle if no description
      description = subtitle_parts.join(' • ') if description.blank? && subtitle_parts.any?

      return nil unless title.present?

      {
        'title' => title.truncate(100),
        'url' => url,
        'description' => description&.truncate(200)
      }.compact
    end

    # Find first non-empty string value from a list of keys
    def find_first_string(hash, keys)
      keys.each do |key|
        value = hash[key]
        return value if value.is_a?(String) && value.present?
      end
      nil
    end

    # Find first URL from common locations
    def find_first_url(hash)
      # Direct URL fields (htmlLink for Google Calendar)
      %w[url href link uri web_url html_url htmlLink permalink].each do |key|
        value = hash[key]
        return value if value.is_a?(String) && value.start_with?('http')
      end

      # Nested external_urls (Spotify style)
      if hash['external_urls'].is_a?(Hash)
        hash['external_urls'].each_value do |url|
          return url if url.is_a?(String) && url.start_with?('http')
        end
      end

      # Nested url object
      if hash['url'].is_a?(Hash)
        return hash['url']['web'] || hash['url']['href'] || hash['url']['link']
      end

      nil
    end

    # Validate tool_activity structure follows iOS contract
    # Ensures consistent metadata structure across all tools
    def validate_tool_activity_structure!(tool_activity, tool_name)
      # Required keys
      required_keys = ['id', 'name', 'status', 'input']
      missing_keys = required_keys - tool_activity.keys.map(&:to_s)

      if missing_keys.any?
        raise ArgumentError, "tool_activity missing required keys: #{missing_keys.join(', ')} for tool: #{tool_name}"
      end

      # Verify no flattened result data (should all be in 'data' key)
      # Common mistakes: note_id, task_id, etc. at top level instead of in data
      forbidden_top_level = tool_activity.keys.map(&:to_s) - ['id', 'name', 'status', 'input', 'data', 'display_message', 'error']

      if forbidden_top_level.any?
        Rails.logger.warn("[Registry] tool_activity has unexpected top-level keys: #{forbidden_top_level.join(', ')} for tool: #{tool_name}. " \
                          "All tool results should be in 'data' key.")
      end

      true
    end

    # Extract a meaningful display message from MCP tool results
    # Parses the nested JSON in MCP responses to find useful info
    # Uses generic patterns rather than hardcoding tool-specific logic
    def extract_mcp_display_message(tool_name, result)
      return nil unless result.is_a?(Hash)

      # Try to find the actual result content
      content_text = nil
      if result['content'].is_a?(Array) && result['content'].first.is_a?(Hash)
        content_text = result['content'].first['text']
      elsif result[:result].is_a?(String)
        content_text = result[:result]
      end

      return nil unless content_text.is_a?(String)

      begin
        parsed = JSON.parse(content_text)
        extract_display_from_json(parsed, tool_name)
      rescue JSON::ParserError
        nil
      end
    end

    # Recursively extract meaningful display info from JSON
    # Looks for common patterns: arrays (count), name fields, URLs
    def extract_display_from_json(data, tool_name = nil)
      return nil unless data.is_a?(Hash)

      # Determine action verb from tool name
      action = infer_action_from_tool_name(tool_name)

      # Check for result arrays first (results, items, data, records, entries)
      array_keys = %w[results items data records entries events messages tasks notes]
      array_keys.each do |key|
        if data[key].is_a?(Array) && data[key].any?
          items = data[key]
          count = items.size

          # If single result, try to extract its name
          if count == 1 && items.first.is_a?(Hash)
            name = extract_name_from_hash(items.first)
            return "#{action}: #{name}" if name.present?
          end

          # Multiple results - show count
          item_type = key.singularize
          return "#{action == 'Done' ? 'Found' : action}: #{count} #{item_type}#{'s' if count != 1}"
        end
      end

      # Check for a direct name/title at top level
      name = extract_name_from_hash(data)
      return "#{action}: #{name}" if name.present?

      # Check for success/message fields
      if data['message'].is_a?(String) && data['message'].length < 100
        return data['message']
      end

      nil
    end

    # Extract a human-readable name from a hash
    # Looks for common name fields in priority order
    def extract_name_from_hash(hash)
      return nil unless hash.is_a?(Hash)

      # Priority order for name fields
      name_keys = %w[name title subject label display_name filename summary headline]
      name_keys.each do |key|
        value = hash[key]
        return value.truncate(50) if value.is_a?(String) && value.present?
      end

      # Try to find artist/author for media items
      artist = hash.dig('artists', 0, 'name') || hash['artist'] || hash['author']
      if artist.present? && hash['name'].present?
        return "#{hash['name']} by #{artist}".truncate(60)
      end

      nil
    end

    # Infer the action verb from the tool name
    def infer_action_from_tool_name(tool_name)
      return 'Done' unless tool_name.is_a?(String)

      case tool_name.downcase
      when /create|add|new|insert|post/
        'Created'
      when /update|edit|modify|patch|put/
        'Updated'
      when /delete|remove|destroy/
        'Deleted'
      when /search|find|query|lookup|get|fetch|list|read/
        'Found'
      when /send|email|message|notify/
        'Sent'
      when /schedule|book|reserve/
        'Scheduled'
      else
        'Done'
      end
    end

    # Generate friendly display message from tool name
    def friendly_tool_message(tool_name)
      case tool_name
      when /web.*search|search.*web/i
        "Searching the web"
      when /search/i
        "Searching"
      when /note/i
        "Jotting down findings"
      when /^mcp_/
        "Gathering information"
      when /create.*playlist|playlist.*create/i
        "Creating playlist"
      when /add.*item|item.*add|add.*track|track.*add/i
        "Adding to playlist"
      when /find.*track|track.*find|get.*track/i
        "Finding track"
      when /spotify/i
        # Generic Spotify action - humanize the tool name
        tool_name.sub('spotify_', '').titleize
      when /calendar|event/i
        "Managing calendar"
      when /email|gmail|mail/i
        "Managing email"
      when /todoist|task/i
        "Managing tasks"
      when /notion/i
        "Working with Notion"
      else
        # For unknown MCP tools, humanize the name
        tool_name.gsub('_', ' ').titleize
      end
    end

    # ---- System tool helpers (centralized here) ----


    # List system tools metadata
    def system_available_tools(restricted: [])
      SYSTEM_TOOLS.map do |name, klass_name|
        next if restricted&.include?(name)
        klass = klass_name.constantize
        meta = klass.metadata
        {
          name: meta[:name] || name,
          description: meta[:description],
          params_hint: meta[:params_hint]
        }
      rescue NameError
        nil
      end.compact
    end

    # Metadata for a single system tool
    def system_metadata_for(name)
      klass_name = SYSTEM_TOOLS[name.to_s]
      return nil unless klass_name
      klass = klass_name.constantize
      klass.metadata
    rescue NameError
      nil
    end

    # (removed AgentActivityLog logging)

    # Create ThreadMessage for ALL tool calls (system and MCP) so they appear in iOS client
    def create_tool_thread_message(tool_name, params, result, activity_id = nil)
      return unless @user && @agentable
      
      # Verify agentable still exists in database
      unless @agentable.class.exists?(@agentable.id)
        Rails.logger.warn("[Registry] #{@agentable.class.name} #{@agentable.id} no longer exists, skipping ThreadMessage creation")
        return
      end
      
      # Use provided activity_id or generate one for consistency
      activity_id = activity_id || SecureRandom.uuid

      # Try to find existing ThreadMessage for this activity_id (from tool start)
      existing_message = ThreadMessage.where(
        user: @user,
        agentable: @agentable,
        source: :agent,
        message_type: :tool,
        tool_activity_id: activity_id
      ).first
      
      if existing_message
        # Update existing message with completion data
        update_tool_thread_message(existing_message, tool_name, params, result, activity_id)
        return
      end
      
      # Build tool activity metadata
      status = determine_tool_status(result)
      tool_activity = {
        id: activity_id,  # iOS client expects "id", not "activity_id"
        name: tool_name,
        status: status,
        input: params
      }
      
      # Add result data if successful
      if status == 'success'
        add_result_data_to_activity(tool_activity, result)
      end

      # Validate structure follows iOS contract (development/test only for performance)
      validate_tool_activity_structure!(tool_activity, tool_name) unless Rails.env.production?

      # Create ThreadMessage with tool activity metadata
      # Client will render tool cell with results based on status: 'success'
      ThreadMessage.create!(
        user: @user,
        agentable: @agentable,
        source: :agent,
        message_type: :tool,
        tool_activity_id: activity_id, # Indexed for efficient queries
        content: "Tool executed: #{tool_name}",
        metadata: {
          references: {},
          tool_activity: tool_activity
        }
      )
    rescue => e
      # Log error but don't fail the tool execution
      Rails.logger.error("[Registry] Failed to create MCP tool ThreadMessage: #{e.message}")
    end

    # Update existing ThreadMessage when tool completes
    def update_tool_thread_message(message, tool_name, params, result, activity_id)
      # Build updates hash
      status = determine_tool_status(result)
      updates = { status: status }

      # Store error message if tool failed (used for retry detection)
      if status == 'failure'
        error_msg = result[:error] || result['error'] || result[:observation] || 'Unknown error'
        updates[:error] = error_msg
      end

      # Handle emit_task_progress messages (agent custom message)
      if result[:message].present?
        updates[:display_message] = result[:message]
      elsif status == 'success'
        # Try to extract a meaningful display message from MCP results
        extracted_message = extract_mcp_display_message(tool_name, result)
        updates[:display_message] = extracted_message if extracted_message.present?
      end

      # Add result data (mutates updates hash to add 'data' key)
      add_result_data_to_activity(updates, result)

      # Apply all updates at once
      message.update_tool_activity(updates)

      # Handle deletions separately
      fields_to_delete = []
      fields_to_delete << :error if status != 'failure'
      fields_to_delete << :display_message if result[:task_status] == 'completed'

      message.delete_tool_activity_fields(fields_to_delete) if fields_to_delete.any?

      # Validate structure follows iOS contract (development/test only for performance)
      current_activity = message.reload.metadata['tool_activity']
      validate_tool_activity_structure!(current_activity, tool_name) unless Rails.env.production?

      # Clear content to trigger auto-generation
      message.update!(content: "")
    rescue => e
      Rails.logger.error("[Registry] Failed to update tool thread message: #{e.message}")
    end

    # Extract MCP content and format for CoreLoop/LLM consumption
    # MCP returns: { content: [{ type: 'text', text: '...' }] }
    # CoreLoop expects: { result: '...', success: true }
    def enhance_mcp_result(tool_name, params, result)
      # If result already has the expected format, return as-is
      return result if result.is_a?(Hash) && result.key?(:result)

      # Check if MCP call was successful
      # MCP tools may or may not include 'isError' field:
      # - isError: true explicitly indicates failure
      # - isError: false or missing (nil) with content indicates success
      # IMPORTANT: Absence of isError does NOT mean failure!
      has_explicit_error = result.is_a?(Hash) && result['isError'] == true
      has_content = result.is_a?(Hash) && result['content'].present?
      mcp_success = has_content && !has_explicit_error

      # Extract the actual content from MCP format
      content_text = if result.is_a?(Hash) && result['content'].is_a?(Array)
                       content_block = result['content'].first
                       content_block.is_a?(Hash) ? (content_block['text'] || '') : ''
                     elsif result.is_a?(Hash) && result['content'].is_a?(String)
                       result['content']
                     else
                       ''
                     end

      # If content looks like an error message, treat as failure regardless of isError flag
      if content_text.to_s.include?('Tool execution failed') || content_text.to_s.include?('execution failed')
        mcp_success = false
      end

      # Return the result in the format CoreLoop expects
      # For MCP tools, the content is already well-formatted by the MCP server
      if mcp_success
        {
          success: true,
          result: content_text.present? ? content_text : 'Success',
          isError: false
        }
      else
        # Extract error message from various possible locations
        error_msg = result['error'] || result[:error]

        # If no direct error field, try to extract from content if it's an error response
        if error_msg.blank? && result.is_a?(Hash) && result['content'].is_a?(Array)
          content_block = result['content'].first
          error_msg = content_block['text'] if content_block.is_a?(Hash)
        end

        # Fallback to generic message with tool name for better debugging
        error_msg = "Tool '#{tool_name}' execution failed (no error details provided)" if error_msg.blank?

        # Truncate very long error messages but keep enough for debugging
        error_msg = error_msg.to_s.truncate(500) if error_msg.to_s.length > 500

        Rails.logger.warn("[Registry] MCP tool '#{tool_name}' failed with error: #{error_msg}")

        {
          success: false,
          error: error_msg,
          result: error_msg,
          isError: true
        }
      end
    end
  end
end
