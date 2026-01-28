# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Mcp
  # Minimal JSON-RPC 2.0 client for HTTP(S) endpoints with MCP session support
  class JsonRpc
    def initialize(endpoint:, headers: {})
      @endpoint = URI.parse(endpoint)
      @base_headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json, text/event-stream'
      }.merge(headers || {})
      @id = 0
      @session_id = nil
      @initialized = false
    end

    def call(method, params = {})
      # Initialize session if needed (for MCP servers that require it)
      ensure_initialized! unless method == 'initialize'

      @id += 1
      payload = { jsonrpc: '2.0', id: @id, method: method, params: params }

      headers = @base_headers.dup
      headers['Mcp-Session-Id'] = @session_id if @session_id

      res = make_request(payload, headers)

      # Extract session ID from response header
      if res['Mcp-Session-Id'] && !@session_id
        @session_id = res['Mcp-Session-Id']
        Rails.logger.info("[MCP] Received session ID: #{@session_id[0..20]}...")
      end

      # Parse SSE response format (event: message\ndata: {...})
      body = res.body.to_s
      data = parse_sse_response(body)

      raise "MCP HTTP #{res.code}: #{body[0..200]}" unless res.code.to_i.between?(200, 299)

      if data['error']
        raise "MCP RPC error: #{data['error'].inspect}"
      end
      data['result']
    end

    private

    def ensure_initialized!
      return if @initialized

      # Step 1: Send initialize request
      @id += 1
      payload = {
        jsonrpc: '2.0',
        id: @id,
        method: 'initialize',
        params: {
          protocolVersion: '2024-11-05',
          capabilities: {},
          clientInfo: { name: 'houston-backend', version: '1.0' }
        }
      }

      res = make_request(payload, @base_headers)

      # Extract session ID from response header
      if res['Mcp-Session-Id']
        @session_id = res['Mcp-Session-Id']
        Rails.logger.info("[MCP] Initialized with session ID: #{@session_id[0..20]}...")
      end

      # Step 2: Send initialized notification (required by MCP protocol)
      if @session_id
        notification = { jsonrpc: '2.0', method: 'notifications/initialized' }
        headers = @base_headers.merge('Mcp-Session-Id' => @session_id)
        make_request(notification, headers)
        Rails.logger.info("[MCP] Sent initialized notification")
      end

      @initialized = true
    end

    def make_request(payload, headers)
      req = Net::HTTP::Post.new(@endpoint.request_uri)
      headers.each { |k, v| req[k] = v }
      req.body = JSON.dump(payload)

      http = Net::HTTP.new(@endpoint.host, @endpoint.port)
      http.use_ssl = (@endpoint.scheme == 'https')
      http.read_timeout = 30
      http.open_timeout = 5
      http.request(req)
    end

    def parse_sse_response(body)
      Mcp::ResponseParser.parse(body, context: "[MCP JsonRpc]") || { 'error' => { 'message' => "Invalid response: #{body[0..200]}" } }
    end
  end
end
