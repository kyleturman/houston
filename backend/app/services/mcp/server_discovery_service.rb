# frozen_string_literal: true

require 'net/http'
require 'json'

module Mcp
  # Service for discovering MCP server authentication requirements.
  # Tries to connect without auth first, then falls back to OAuth discovery.
  class ServerDiscoveryService
    # Result of server discovery
    class DiscoveryResult
      attr_reader :auth_type, :status, :server_info, :oauth_metadata, :error

      # @param auth_type [Symbol] :none, :oauth, or :unknown
      # @param status [Symbol] :success, :needs_auth, or :error
      # @param server_info [Hash] Server metadata from initialize response
      # @param oauth_metadata [Hash] OAuth endpoints if discovered
      # @param error [String] Error message if failed
      def initialize(auth_type:, status:, server_info: nil, oauth_metadata: nil, error: nil)
        @auth_type = auth_type
        @status = status
        @server_info = server_info
        @oauth_metadata = oauth_metadata
        @error = error
      end

      def success?
        status == :success
      end

      def needs_auth?
        status == :needs_auth
      end

      def error?
        status == :error
      end
    end

    class << self
      # Discover what authentication a server requires
      # @param url [String] The MCP server URL
      # @return [DiscoveryResult]
      def discover(url)
        uri = URI(url)
        Rails.logger.info("[ServerDiscovery] Discovering auth for #{url}")

        # Step 1: Try connecting without auth
        result = try_connect_no_auth(uri)

        if result.success?
          Rails.logger.info("[ServerDiscovery] Server #{url} requires no auth")
          return result
        end

        # Step 2: If 401/403, try OAuth discovery
        if result.needs_auth?
          Rails.logger.info("[ServerDiscovery] Server #{url} requires auth, trying OAuth discovery")
          oauth_result = discover_oauth(uri)
          return oauth_result if oauth_result.oauth_metadata.present?

          # OAuth discovery failed, return original needs_auth result
          Rails.logger.info("[ServerDiscovery] OAuth discovery failed for #{url}")
        end

        result
      end

      private

      # Try to connect to server without authentication
      def try_connect_no_auth(uri)
        http = build_http_client(uri)

        # Send MCP initialize request
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json, text/event-stream'
        request.body = build_initialize_request.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          # Success - no auth needed
          data = parse_response(response.body)
          server_info = data&.dig('result', 'serverInfo')
          DiscoveryResult.new(
            auth_type: :none,
            status: :success,
            server_info: server_info
          )
        when 401, 403
          # Needs authentication
          DiscoveryResult.new(
            auth_type: :unknown,
            status: :needs_auth
          )
        else
          DiscoveryResult.new(
            auth_type: :unknown,
            status: :error,
            error: "Server returned HTTP #{response.code}"
          )
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        DiscoveryResult.new(
          auth_type: :unknown,
          status: :error,
          error: "Connection timeout: #{e.message}"
        )
      rescue StandardError => e
        Rails.logger.warn("[ServerDiscovery] Connection failed: #{e.message}")
        DiscoveryResult.new(
          auth_type: :unknown,
          status: :error,
          error: e.message
        )
      end

      # Try to discover OAuth endpoints via well-known URLs
      def discover_oauth(uri)
        server_base = "#{uri.scheme}://#{uri.host}"
        server_base += ":#{uri.port}" unless [80, 443].include?(uri.port)

        # Use RemoteOauthService's discovery logic
        oauth_metadata = RemoteOauthService.discover_oauth_metadata(server_base)

        DiscoveryResult.new(
          auth_type: :oauth,
          status: :needs_auth,
          oauth_metadata: oauth_metadata
        )
      rescue RemoteOauthService::DiscoveryError => e
        Rails.logger.info("[ServerDiscovery] OAuth discovery failed: #{e.message}")
        DiscoveryResult.new(
          auth_type: :unknown,
          status: :needs_auth,
          error: "Server requires authentication but OAuth discovery failed: #{e.message}"
        )
      end

      def build_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 15
        http
      end

      def build_initialize_request
        {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'initialize',
          params: {
            protocolVersion: '2024-11-05',
            capabilities: {},
            clientInfo: { name: 'houston', version: '1.0' }
          }
        }
      end

      def parse_response(body)
        Mcp::ResponseParser.parse(body, context: "[ServerDiscovery]")
      end
    end
  end
end
