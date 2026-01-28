# frozen_string_literal: true

module Auth
  class SigninRequestController < ApplicationController
    include MagicLinkSender

    # POST /api/auth/request_signin
    # Params: { email: string }
    # Rate limited to prevent abuse
    # Always returns success to prevent email enumeration
    def create
      email = params.require(:email).to_s.strip.downcase

      # IP rate limit
      ip_limit = Auth::RateLimiter.check_ip_limit(request.remote_ip)
      unless ip_limit[:allowed]
        Rails.logger.warn("[SigninRequest] IP rate limited: #{request.remote_ip}")
        return render json: {
          error: "Too many requests",
          retry_after: ip_limit[:retry_after]
        }, status: :too_many_requests
      end

      # Email rate limit
      email_limit = Auth::RateLimiter.check_email_limit(email)
      unless email_limit[:allowed]
        Rails.logger.warn("[SigninRequest] Email rate limited: #{email}")
        return render json: {
          error: "Too many requests for this email",
          retry_after: email_limit[:retry_after]
        }, status: :too_many_requests
      end

      # Find user and send magic link if exists and active
      user = User.find_by(email: email)
      if user&.active?
        if send_magic_link(user, context: 'app')
          Rails.logger.info("[SigninRequest] Magic link sent to #{email}")
        else
          Rails.logger.error("[SigninRequest] Failed to send magic link to #{email}")
        end
      else
        Rails.logger.info("[SigninRequest] No active user found for #{email}")
      end

      # Always return success to prevent email enumeration
      render json: {
        success: true,
        message: "If an account exists, a sign-in link has been sent"
      }, status: :ok
    end
  end
end
