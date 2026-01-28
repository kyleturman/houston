# frozen_string_literal: true
require "socket"
require "uri"

# Derive default URL options from IP if SERVER_PUBLIC_URL is not set.
# We prefer an IP-based URL to simplify pairing on local networks.
#
# Heuristics:
# - If SERVER_PUBLIC_URL is present, we do nothing (mailer.rb will parse it).
# - Otherwise, find the first private IPv4 address on the host (RFC1918 ranges).
# - Build URL using protocol derived from FORCE_SSL (https if true, else http) and port from PORT (default 3000).
#
# Caveat: When using Cloudflare Tunnel, the public entrypoint is a hostname on Cloudflare and
# does not have a stable, dedicated public IP that you can share directly. In that case, set
# SERVER_PUBLIC_URL explicitly to your tunnel hostname.
Rails.application.config.to_prepare do
  next if ENV["SERVER_PUBLIC_URL"].present?

  def private_ipv4?(addr)
    return false unless addr.ipv4? && !addr.ipv4_loopback?
    octets = addr.ip_address.split(".").map(&:to_i)
    # 10.0.0.0/8
    return true if octets[0] == 10
    # 172.16.0.0/12
    return true if octets[0] == 172 && (16..31).include?(octets[1])
    # 192.168.0.0/16
    return true if octets[0] == 192 && octets[1] == 168
    false
  end

  ip = Socket.ip_address_list.find { |a| private_ipv4?(a) }&.ip_address

  if ip
    protocol = ENV["FORCE_SSL"].to_s.downcase == "true" ? "https" : "http"
    port = (ENV["PORT"].presence || 3000).to_i
    # Omit default ports for cleanliness in URLs
    port_part = if (protocol == "http" && port == 80) || (protocol == "https" && port == 443)
      nil
    else
      ":#{port}"
    end

    derived_url = "#{protocol}://#{ip}#{port_part}"
    # Apply to action_mailer default_url_options if not already set elsewhere
    begin
      uri = URI.parse(derived_url)
      Rails.application.config.action_mailer.default_url_options ||= {}
      Rails.application.config.action_mailer.default_url_options.merge!(host: uri.host, protocol: uri.scheme)
      Rails.application.config.action_mailer.default_url_options[:port] = uri.port if port_part
    rescue URI::InvalidURIError
      # ignore if we fail to parse
    end
  end
end
