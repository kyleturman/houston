# frozen_string_literal: true

module Auth
  class SigninController < ActionController::Base
    include JwtAuth
    include MagicLinkSender

    # Skip CSRF for this controller since it's accessed via email links
    skip_before_action :verify_authenticity_token

    # GET /auth/signin?token=JWT
    def show
      unless params[:token].present?
        return render_error("Missing sign-in token.")
      end

      token = params[:token]

      # Check IP-based rate limit first
      ip_limit = Auth::RateLimiter.check_ip_limit(request.remote_ip)
      unless ip_limit[:allowed]
        Rails.logger.warn("[Signin] IP rate limited: #{request.remote_ip}")
        return render_rate_limited(ip_limit[:retry_after])
      end

      # Try to decode and validate token
      begin
        # Decode JWT directly to catch ExpiredSignature before it gets wrapped
        decoded, = JWT.decode(token, pairing_jwt_secret, true, { algorithm: 'HS256' })

        # Validate token type
        unless decoded['typ'] == 'signin'
          Rails.logger.error("[Signin] Invalid token type: #{decoded['typ']}")
          return render_error("Invalid sign-in link. Please request a new link.")
        end

        email = decoded["sub"]
        jti = decoded["jti"]

        # Check email-based rate limit
        email_limit = Auth::RateLimiter.check_email_limit(email)
        unless email_limit[:allowed]
          Rails.logger.warn("[Signin] Email rate limited: #{email}")
          return render_rate_limited(email_limit[:retry_after])
        end

        # Check if token was already used
        if Auth::TokenTracker.used?(jti)
          Rails.logger.warn("[Signin] Token already used: #{jti}")
          return render_error("This sign-in link has already been used. Please request a new link.")
        end

        # Valid token - mark as used and redirect based on context
        Auth::TokenTracker.mark_used(jti, ttl: 900)

        context = decoded['ctx'] || 'app'
        user = User.find_by(email: email)

        if context == 'admin'
          handle_admin_signin(user, token)
        else
          Rails.logger.info("[Signin] Valid token for #{email}, redirecting to app")
          redirect_to_app(token, email)
        end

      rescue JWT::ExpiredSignature
        # Token expired - extract email and send fresh link
        handle_expired_token(token)

      rescue JWT::DecodeError => e
        Rails.logger.error("[Signin] JWT decode error: #{e.message}")
        render_error("Invalid sign-in link. Please request a new link.")
      end
    end

    private

    def handle_expired_token(token)
      # Decode without verification to extract email
      begin
        decoded = JWT.decode(token, pairing_jwt_secret, false, { algorithm: 'HS256' })
        email = decoded[0]["sub"]

        # Check email-based rate limit
        email_limit = Auth::RateLimiter.check_email_limit(email)
        unless email_limit[:allowed]
          Rails.logger.warn("[Signin] Email rate limited on expired token: #{email}")
          return render_rate_limited(email_limit[:retry_after])
        end

        # Find user and send fresh magic link
        user = User.find_by(email: email)
        unless user
          Rails.logger.error("[Signin] User not found for expired token: #{email}")
          return render_error("User not found. Please contact your administrator.")
        end

        # Send fresh magic link
        if send_magic_link(user)
          Rails.logger.info("[Signin] Sent fresh magic link to #{email}")
          render_token_refreshed
        else
          render_error("Failed to send sign-in link. Please try again or contact your administrator.")
        end

      rescue JWT::DecodeError => e
        Rails.logger.error("[Signin] Failed to decode expired token: #{e.message}")
        render_error("Invalid sign-in link. Please request a new link.")
      end
    end

    def redirect_to_app(token, email)
      # Build deep link for iOS app
      # Note: server_name is no longer passed in the deep link - it's returned by the claim endpoint
      scheme = ENV["APP_URL_SCHEME"].presence || "heyhouston"
      server_url = ENV['SERVER_PUBLIC_URL'].presence || request.base_url

      deep_link = "#{scheme}://signin?token=#{CGI.escape(token)}&url=#{CGI.escape(server_url)}&email=#{CGI.escape(email)}"

      render 'auth/signin/redirecting', locals: { deep_link: deep_link }, layout: false
    end

    def render_token_refreshed
      render 'auth/signin/token_refreshed', status: :ok, layout: false
    end

    def render_rate_limited(retry_after)
      render 'auth/signin/rate_limited', locals: { retry_after: retry_after }, status: :too_many_requests, layout: false
    end

    def render_error(message)
      render 'auth/signin/error', locals: { error_message: message }, status: :bad_request, layout: false
    end

    def handle_admin_signin(user, token)
      unless user
        Rails.logger.error("[Signin] User not found for admin signin")
        return render_error("User not found. Please contact your administrator.")
      end

      unless user.admin?
        Rails.logger.warn("[Signin] Non-admin user attempted admin signin: #{user.email}")
        return render_error("You don't have admin access.")
      end

      # Set session for admin auth
      session[:user_id] = user.id
      session[:admin_authenticated] = true

      Rails.logger.info("[Signin] Admin signin successful for #{user.email}")

      redirect_to '/admin', allow_other_host: false
    end
  end
end
