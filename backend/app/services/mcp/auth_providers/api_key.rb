# frozen_string_literal: true

module Mcp
  module AuthProviders
    # API Key authentication provider (reusable for many services)
    class ApiKey < Base
      def initiate(user:, redirect_uri: nil)
        {
          type: 'api_key',
          fields: config.dig('ios', 'fields') || [
            { key: 'apiKey', label: 'API Key', secure: true }
          ]
        }
      end

      def exchange(user:, credentials:, metadata: {})
        # Just store credentials as-is, optionally merge any metadata
        {
          credentials: credentials,
          metadata: metadata,
          connection_identifier: "api_key_#{user.id}_#{SecureRandom.hex(4)}"
        }
      end
    end
  end
end
