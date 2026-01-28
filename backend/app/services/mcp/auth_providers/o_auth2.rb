# frozen_string_literal: true

module Mcp
  module AuthProviders
    class OAuth2 < Base
      def initiate(user:, redirect_uri: nil)
        # Generate state for CSRF protection
        state = SecureRandom.urlsafe_base64(32)

        # Get the scope based on server's auth_scope
        auth_scope = server.metadata&.dig('auth_scope') || 'default'
        scope = config.dig('scopes', auth_scope) || ''

        # Build the authorization URL from config
        authorize_config = config.dig('backend', 'authorizeEndpoint')
        authorize_url_base = authorize_config['url']

        # Use server-side callback (many OAuth providers don't allow custom schemes)
        # Prefer SERVER_PUBLIC_URL (ngrok) even in development for mobile OAuth
        server_base_url = ENV['SERVER_PUBLIC_URL'].presence || "http://localhost:#{ENV.fetch('PORT', 3033)}"
        server_callback_uri = "#{server_base_url}/api/mcp/oauth/callback"

        # App scheme for final redirect back to app
        app_redirect_scheme = config.dig('ios', 'callback_scheme') || 'heyhouston'

        params = {
          client_id: oauth_credentials[:client_id],
          redirect_uri: server_callback_uri,
          response_type: 'code',
          scope: scope,
          state: state,
          access_type: 'offline',
          prompt: 'consent'
        }

        auth_url = "#{authorize_url_base}?#{params.to_query}"

        # Store state in cache for verification during callback
        Rails.cache.write("oauth_state:#{state}", {
          user_id: user.id,
          server_name: server.name,
          redirect_uri: server_callback_uri,
          app_redirect_scheme: app_redirect_scheme
        }, expires_in: 10.minutes)

        {
          type: 'oauth2',
          handler: config.dig('ios', 'handler') || 'oauth2',
          linkToken: auth_url,
          authUrl: auth_url,
          state: state,
          redirectUri: server_callback_uri,
          iosConfig: config['ios']&.merge('callback_scheme' => app_redirect_scheme)
        }
      end

      def exchange(user:, credentials:, metadata: {})
        code = credentials[:code] || credentials['code']
        state = credentials[:state] || credentials['state']
        redirect_uri = credentials[:redirect_uri] || credentials['redirect_uri']

        # Verify state if provided
        if state.present?
          cached = Rails.cache.read("oauth_state:#{state}")
          if cached && cached[:user_id] != user.id
            raise Mcp::AuthService::AuthError, "Invalid OAuth state"
          end
          Rails.cache.delete("oauth_state:#{state}")
          redirect_uri ||= cached&.dig(:redirect_uri)
        end

        token_response = exchange_code_for_token(code, redirect_uri)

        # For Google OAuth, fetch user email to use as account identifier
        if provider_name == 'google'
          user_info = fetch_google_user_info(token_response['access_token'])
          metadata = metadata.merge('email' => user_info['email']) if user_info['email']
        end

        {
          credentials: {
            access_token: token_response['access_token'],
            refresh_token: token_response['refresh_token'],
            expires_at: token_response['expires_in'] ? Time.current + token_response['expires_in'].to_i.seconds : nil,
            token_type: token_response['token_type']
          },
          metadata: metadata.merge(
            provider: provider_name,
            scope: token_response['scope']
          ),
          connection_identifier: "#{provider_name}_#{user.id}_#{SecureRandom.hex(4)}"
        }
      end

      def refresh(connection:)
        refresh_token = connection.parsed_credentials['refresh_token']
        raise Mcp::AuthService::AuthError, "No refresh token available" unless refresh_token

        response = refresh_access_token(refresh_token)

        connection.update!(
          credentials: connection.parsed_credentials.merge(
            'access_token' => response['access_token'],
            'expires_at' => response['expires_in'] ? Time.current + response['expires_in'].to_i.seconds : nil
          ).to_json
        )

        connection
      end

      private

      # Load OAuth credentials from file or env vars
      def oauth_credentials
        @oauth_credentials ||= load_oauth_credentials
      end

      def load_oauth_credentials
        # Try credentials file first
        if (creds_file = config.dig('backend', 'credentialsFile'))
          creds_path = Rails.root.join('mcp', creds_file)
          if File.exist?(creds_path)
            creds_data = JSON.parse(File.read(creds_path))
            # Support Google's "installed" format or flat format
            if creds_data['installed']
              return {
                client_id: creds_data['installed']['client_id'],
                client_secret: creds_data['installed']['client_secret']
              }
            elsif creds_data['web']
              return {
                client_id: creds_data['web']['client_id'],
                client_secret: creds_data['web']['client_secret']
              }
            else
              return {
                client_id: creds_data['client_id'],
                client_secret: creds_data['client_secret']
              }
            end
          end
        end

        # Fall back to env vars if specified
        if (env_vars = config.dig('backend', 'credentialsEnv'))
          return {
            client_id: ENV[env_vars[0]],
            client_secret: ENV[env_vars[1]]
          }
        end

        raise Mcp::AuthService::AuthError, "No OAuth credentials configured for #{provider_name}"
      end

      # Derive provider name from auth provider filename
      def provider_name
        @provider_name ||= begin
          # Extract from auth provider path (e.g., "auth-providers/google-oauth.json" -> "google")
          auth_provider_path = server.metadata&.dig('auth_provider') || ''
          basename = File.basename(auth_provider_path, '.json')
          basename.sub(/-oauth$/, '')
        end
      end

      def token_endpoint_url
        config.dig('backend', 'tokenEndpoint', 'url')
      end

      def exchange_code_for_token(code, redirect_uri)
        uri = URI(token_endpoint_url)

        body = {
          client_id: oauth_credentials[:client_id],
          client_secret: oauth_credentials[:client_secret],
          code: code,
          redirect_uri: redirect_uri,
          grant_type: 'authorization_code'
        }

        response = Net::HTTP.post_form(uri, body)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = JSON.parse(response.body) rescue {}
          raise Mcp::AuthService::AuthError,
                "Token exchange failed: #{error_body['error_description'] || error_body['error'] || response.message}"
        end

        JSON.parse(response.body)
      end

      def refresh_access_token(refresh_token)
        # Use refresh endpoint if specified, otherwise use token endpoint
        refresh_url = config.dig('backend', 'refreshEndpoint', 'url') || token_endpoint_url
        uri = URI(refresh_url)

        body = {
          client_id: oauth_credentials[:client_id],
          client_secret: oauth_credentials[:client_secret],
          refresh_token: refresh_token,
          grant_type: 'refresh_token'
        }

        response = Net::HTTP.post_form(uri, body)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = JSON.parse(response.body) rescue {}
          raise Mcp::AuthService::AuthError,
                "Token refresh failed: #{error_body['error_description'] || error_body['error'] || response.message}"
        end

        JSON.parse(response.body)
      end

      # Fetch Google user info to get email for multi-account identification
      def fetch_google_user_info(access_token)
        uri = URI('https://www.googleapis.com/oauth2/v2/userinfo')
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{access_token}"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        JSON.parse(response.body)
      rescue => e
        Rails.logger.error("[MCP] Failed to fetch Google user info: #{e.message}")
        { 'email' => nil }
      end
    end
  end
end
