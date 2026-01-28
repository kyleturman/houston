# frozen_string_literal: true

# Shared server configuration helpers
# Provides consistent server URL and display name resolution
module ServerConfig
  extend ActiveSupport::Concern

  def server_public_url
    ENV['SERVER_PUBLIC_URL'].presence ||
      (respond_to?(:request) && request ? request.base_url : default_local_url)
  end

  def server_display_name
    ENV['SERVER_DISPLAY_NAME'].presence ||
      Socket.gethostname.presence ||
      parsed_host_from_url ||
      'My Server'
  end

  # Build a deep link for invite token sign-in
  # Format: heyhouston://signin?url=https://server.com&email=user@example.com&token=ABC123&name=Server&type=invite
  def build_invite_deep_link(email:, token:)
    scheme = ENV['APP_URL_SCHEME'].presence || 'heyhouston'
    params = {
      url: server_public_url,
      email: email,
      token: token,
      name: server_display_name,
      type: 'invite'
    }.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
    "#{scheme}://signin?#{params}"
  end

  private

  def default_local_url
    port = ENV.fetch('PORT', 3033)
    "http://localhost:#{port}"
  end

  def parsed_host_from_url
    uri = URI.parse(server_public_url)
    uri&.host
  rescue URI::InvalidURIError
    nil
  end
end
