# frozen_string_literal: true
require "uri"

# Simple module to check email configuration status app-wide
module EmailConfig
  def self.enabled?
    ENV["EMAIL_PROVIDER"].present?
  end
end

# Configures ActionMailer based on environment variables set by the setup wizard.
# Supported providers:
# - Resend (via SMTP relay)
# - Gmail (App Password required)
# - Amazon SES (SMTP credentials)
# - Custom SMTP
#
# Env vars consumed:
#   EMAIL_PROVIDER: resend|gmail|ses|custom (enables SMTP config if present)
#   MAIL_FROM: default from address
#   SMTP_ADDRESS, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_AUTH, SMTP_DOMAIN, SMTP_ENABLE_STARTTLS
#   SMTP_TLS, SMTP_OPEN_TIMEOUT, SMTP_READ_TIMEOUT

Rails.application.config.to_prepare do
  # Default from address
  default_from = ENV.fetch("MAIL_FROM", "no-reply@localhost")
  ApplicationMailer.default from: default_from

  # Default URL options derived from SERVER_PUBLIC_URL if present
  if (public_url = ENV["SERVER_PUBLIC_URL"]).present?
    begin
      uri = URI.parse(public_url)
      host = uri.host
      protocol = uri.scheme
      port = uri.port
      # Omit default ports for cleanliness
      port_opt = if (protocol == "http" && port == 80) || (protocol == "https" && port == 443)
        nil
      else
        port
      end
      Rails.application.config.action_mailer.default_url_options = { host: host, protocol: protocol }.tap { |h| h[:port] = port_opt if port_opt }
    rescue URI::InvalidURIError
      Rails.logger.warn("SERVER_PUBLIC_URL is invalid: #{public_url.inspect}")
    end
  end

  provider = ENV["EMAIL_PROVIDER"].to_s
  if provider.present?
    port = (ENV["SMTP_PORT"] || 587).to_i
    use_tls = (ENV["SMTP_TLS"].to_s.downcase == "true") || port == 465
    open_timeout = ENV["SMTP_OPEN_TIMEOUT"].to_i if ENV["SMTP_OPEN_TIMEOUT"].present?
    read_timeout = ENV["SMTP_READ_TIMEOUT"].to_i if ENV["SMTP_READ_TIMEOUT"].present?
    smtp_settings = {
      address:              ENV["SMTP_ADDRESS"],
      port:                 port,
      user_name:            ENV["SMTP_USERNAME"],
      password:             ENV["SMTP_PASSWORD"],
      authentication:       (ENV["SMTP_AUTH"].presence || :plain).to_sym,
      domain:               ENV["SMTP_DOMAIN"].presence,
      enable_starttls_auto: (ENV["SMTP_ENABLE_STARTTLS"].to_s != "false") && !use_tls,
      tls:                  use_tls,
      open_timeout:         open_timeout,
      read_timeout:         read_timeout
    }.compact

    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = smtp_settings

    # Surface errors during setup/validation
    Rails.application.config.action_mailer.raise_delivery_errors = true
    Rails.application.config.action_mailer.perform_caching = false
    Rails.application.config.action_mailer.perform_deliveries = true
  end
end

# Ensure delivery errors are raised even when to_prepare does not run (e.g., in `rails runner`).
# This intentionally overrides the development default of suppressing mail errors when an EMAIL_PROVIDER is configured.
if ENV["EMAIL_PROVIDER"].present?
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.perform_deliveries = true
end
