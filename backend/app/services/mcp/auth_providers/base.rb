# frozen_string_literal: true

module Mcp
  module AuthProviders
    # Base class for MCP authentication providers
    # Each provider implements initiate and exchange methods
    class Base
      attr_reader :config, :server

      def initialize(config, server = nil)
        @config = config
        @server = server
      end

      # Initiate auth flow
      # @param user [User] The user initiating auth
      # @param redirect_uri [String] Optional redirect URI
      # @return [Hash] Response to send to client
      def initiate(user:, redirect_uri: nil)
        raise NotImplementedError, "#{self.class} must implement #initiate"
      end

      # Exchange credentials for access token
      # @param user [User] The user
      # @param credentials [Hash] Provider-specific credentials (e.g., public_token, api_key)
      # @param metadata [Hash] Optional client-provided metadata (e.g., institution info, accounts)
      # @return [Hash] { credentials:, metadata:, connection_identifier: }
      def exchange(user:, credentials:, metadata: {})
        raise NotImplementedError, "#{self.class} must implement #exchange"
      end

      # Optional: Disconnect/revoke
      def disconnect(connection:)
        # Override if provider supports revocation
      end

      protected

      # Make HTTP request to provider endpoint
      def make_request(endpoint_config, variables = {})
        require 'net/http'

        url = interpolate(endpoint_config['url'], variables)
        headers = interpolate_hash(endpoint_config['headers'] || {}, variables)
        body = interpolate_hash(endpoint_config['body'] || {}, variables)

        uri = URI(url)
        request = Net::HTTP.const_get(endpoint_config['method'].capitalize).new(uri)

        headers.each { |k, v| request[k] = v }
        request.body = body.to_json if body.present? && endpoint_config['method'].upcase != 'GET'

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          error_data = JSON.parse(response.body) rescue {}
          raise Mcp::AuthService::AuthError, "API request failed: #{error_data['error_message'] || response.message}"
        end

        parse_response(response.body, endpoint_config['response'] || {})
      end

      # Interpolate template variables like {{user_id}}
      def interpolate(template, variables)
        return template unless template.is_a?(String)

        template.gsub(/\{\{(.+?)\}\}/) do
          key = $1.strip
          variables[key] || variables[key.to_sym] || ENV[key] || $&
        end
      end

      # Interpolate hash values
      def interpolate_hash(hash, variables)
        result = {}
        hash.each do |k, v|
          interpolated = case v
                        when String then interpolate(v, variables)
                        when Hash then interpolate_hash(v, variables)
                        else v
                        end

          # Skip keys where interpolation didn't replace the placeholder (still has {{...}})
          next if interpolated.is_a?(String) && interpolated.match?(/\{\{.+?\}\}/)

          result[k] = interpolated
        end
        result
      end

      # Parse response using mapping
      def parse_response(json, mapping)
        data = JSON.parse(json)

        mapping.transform_values do |path|
          # Handle simple key access (e.g., "access_token")
          if path.is_a?(String) && !path.include?('.')
            data[path]
          else
            # Not implementing complex JSON path for now
            data[path]
          end
        end
      end
    end
  end
end
