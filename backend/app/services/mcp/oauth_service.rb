# frozen_string_literal: true

require 'digest'
require 'base64'
require 'securerandom'

module Mcp
  class OauthService
    class << self
      # Generate PKCE code verifier and challenge
      def generate_pkce_pair
        code_verifier = Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
        code_challenge = Base64.urlsafe_encode64(
          Digest::SHA256.digest(code_verifier), 
          padding: false
        )
        
        {
          code_verifier: code_verifier,
          code_challenge: code_challenge,
          code_challenge_method: 'S256'
        }
      end

      # Generate secure state parameter
      def generate_state
        SecureRandom.hex(16)
      end

      # Build OAuth authorization URL
      # @param redirect_uri [String] OAuth callback URL (server endpoint)
      # @param client_redirect_uri [String] Optional URL to redirect client after token exchange (e.g., iOS app URL scheme)
      def build_authorize_url(remote_server, redirect_uri, user, client_redirect_uri: nil)
        oauth_config = remote_server.oauth_config

        raise ArgumentError, "OAuth config missing for #{remote_server.name}" if oauth_config.blank?
        raise ArgumentError, "Authorization URL missing" unless oauth_config['authorize_url']
        raise ArgumentError, "Client ID missing" unless oauth_config['client_id']

        # Generate PKCE parameters if supported
        pkce_params = {}
        code_verifier = nil

        if remote_server.supports_pkce?
          pkce_data = generate_pkce_pair
          pkce_params = {
            code_challenge: pkce_data[:code_challenge],
            code_challenge_method: pkce_data[:code_challenge_method]
          }
          code_verifier = pkce_data[:code_verifier]
        end

        state = generate_state

        # Create or update user connection record
        connection = UserMcpConnection.find_or_initialize_by(
          user: user,
          remote_mcp_server: remote_server
        )
        connection.status = 'pending'
        connection.state = state
        connection.code_verifier = code_verifier
        # Store both redirect URIs:
        # - redirect_uri: OAuth callback URL for token exchange
        # - client_redirect_uri: Where to redirect client after token exchange (e.g., iOS app)
        connection.metadata = (connection.metadata || {}).merge(
          'redirect_uri' => redirect_uri,
          'client_redirect_uri' => client_redirect_uri
        ).compact
        connection.save!

        # Build authorization URL
        params = {
          response_type: 'code',
          client_id: oauth_config['client_id'],
          redirect_uri: redirect_uri,
          state: state,
          scope: oauth_config['scope'] || 'read'
        }.merge(pkce_params)

        uri = URI(oauth_config['authorize_url'])
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end

      # Exchange authorization code for tokens
      def exchange_code_for_tokens(remote_server, code, state, user)
        connection = UserMcpConnection.find_by(
          user: user,
          remote_mcp_server: remote_server,
          state: state,
          status: 'pending'
        )

        raise ArgumentError, "Invalid state or connection not found" unless connection

        oauth_config = remote_server.oauth_config
        raise ArgumentError, "Token URL missing" unless oauth_config['token_url']

        # Prepare token request - use stored redirect_uri from initiation
        stored_redirect_uri = connection.metadata&.dig('redirect_uri')
        token_params = {
          grant_type: 'authorization_code',
          client_id: oauth_config['client_id'],
          code: code,
          redirect_uri: stored_redirect_uri
        }

        # Add PKCE verifier if used
        if connection.code_verifier.present?
          token_params[:code_verifier] = connection.code_verifier
        elsif oauth_config['client_secret'].present?
          token_params[:client_secret] = oauth_config['client_secret']
        end

        # Make token request
        response = make_token_request(oauth_config['token_url'], token_params)
        
        if response['error']
          raise StandardError, "OAuth error: #{response['error']} - #{response['error_description']}"
        end

        # Update connection with tokens
        # Store access_token in encrypted credentials field as JSON
        connection.update!(
          credentials: { 'access_token' => response['access_token'] }.to_json,
          refresh_token: response['refresh_token'],
          expires_at: response['expires_in'] ? Time.current + response['expires_in'].to_i.seconds : nil,
          status: 'authorized',
          metadata: connection.metadata.merge(
            'token_type' => response['token_type'] || 'Bearer',
            'scope' => response['scope']
          ).compact,
          # Clear PKCE data
          code_verifier: nil,
          state: nil
        )

        connection
      end

      # Refresh access token
      def refresh_token(connection)
        return false unless connection.needs_refresh?

        remote_server = connection.remote_mcp_server
        oauth_config = remote_server.oauth_config
        
        raise ArgumentError, "Token URL missing" unless oauth_config['token_url']

        token_params = {
          grant_type: 'refresh_token',
          client_id: oauth_config['client_id'],
          refresh_token: connection.refresh_token
        }

        # Add client secret if available (not needed for PKCE)
        if oauth_config['client_secret'].present?
          token_params[:client_secret] = oauth_config['client_secret']
        end

        response = make_token_request(oauth_config['token_url'], token_params)
        
        if response['error']
          connection.update!(status: 'expired')
          return false
        end

        # Update connection with new tokens
        connection.update!(
          credentials: { 'access_token' => response['access_token'] }.to_json,
          refresh_token: response['refresh_token'] || connection.refresh_token,
          expires_at: response['expires_in'] ? Time.current + response['expires_in'].to_i.seconds : nil,
          status: 'authorized'
        )

        true
      end

      private

      def make_token_request(token_url, params)
        uri = URI(token_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request['Accept'] = 'application/json'
        request.body = URI.encode_www_form(params)

        response = http.request(request)
        JSON.parse(response.body)
      rescue JSON::ParserError
        { 'error' => 'invalid_response', 'error_description' => 'Invalid JSON response from token endpoint' }
      rescue => e
        { 'error' => 'request_failed', 'error_description' => e.message }
      end
    end
  end
end
