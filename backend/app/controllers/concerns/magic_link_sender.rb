# frozen_string_literal: true

# Sends magic sign-in link emails to users
module MagicLinkSender
  extend ActiveSupport::Concern

  included do
    include JwtAuth  # Provides issue_signin_token and ServerConfig
  end

  # Send a magic link email to a user
  # @param user [User] The user to send the link to
  # @param context [String] The context for the token ('app' or 'admin')
  # @return [Boolean] true if email was sent successfully
  def send_magic_link(user, context: 'app')
    token = issue_signin_token(user.email, context: context)

    mailer_method = case context
    when 'admin' then :admin_signin
    else :app_signin
    end

    MagicLinkMailer.with(
      user: user,
      token: token,
      server_url: server_public_url,
      server_name: server_display_name
    ).send(mailer_method).deliver_now

    Rails.logger.info("[MagicLinkSender] Magic link (#{context}) sent to #{user.email}")
    true
  rescue => e
    Rails.logger.error("[MagicLinkSender] Failed to send magic link: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    false
  end
end
