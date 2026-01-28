# frozen_string_literal: true

module Mcp
  module AuthProviders
    # Plaid Link authentication provider
    class PlaidLink < Base
      def initiate(user:, redirect_uri: nil)
        # Use provided redirect_uri, or derive from SERVER_PUBLIC_URL, or fall back to localhost
        base_url = ENV['SERVER_PUBLIC_URL'].presence || "http://localhost:#{ENV.fetch('PORT', 3033)}"
        final_redirect_uri = redirect_uri || "#{base_url}/plaid-oauth"

        variables = {
          'env' => ENV['PLAID_ENV'] || 'sandbox',
          'user_id' => user.id.to_s,
          'redirect_uri' => final_redirect_uri,
          'PLAID_CLIENT_ID' => ENV['PLAID_CLIENT_ID'],
          'PLAID_SECRET' => ENV['PLAID_SECRET']
        }.compact

        link_token_response = make_request(
          config['backend']['linkTokenEndpoint'],
          variables
        )

        {
          type: 'plaid_link',
          handler: config.dig('ios', 'handler') || 'plaid_link',
          linkToken: link_token_response['linkToken'],
          expiration: link_token_response['expiration'],
          iosConfig: config['ios']
        }
      end

      def exchange(user:, credentials:, metadata: {})
        public_token = credentials[:public_token] || credentials['public_token']

        variables = {
          'env' => ENV['PLAID_ENV'] || 'sandbox',
          'public_token' => public_token,
          'PLAID_CLIENT_ID' => ENV['PLAID_CLIENT_ID'],
          'PLAID_SECRET' => ENV['PLAID_SECRET']
        }

        exchange_response = make_request(
          config['backend']['exchangeTokenEndpoint'],
          variables
        )

        {
          credentials: {
            'accessToken' => exchange_response['accessToken'],
            'itemId' => exchange_response['itemId']
          },
          metadata: {
            'institution_name' => metadata.dig('institution', 'name'),
            'institution_id' => metadata.dig('institution', 'institution_id'),
            'accounts' => metadata['accounts'] || []
          },
          connection_identifier: exchange_response['itemId']
        }
      end
    end
  end
end
