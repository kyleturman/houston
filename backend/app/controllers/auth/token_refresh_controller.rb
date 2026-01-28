# frozen_string_literal: true

class Auth::TokenRefreshController < ApplicationController
  include UserJwt

  # POST /auth/refresh
  def create
    authenticate_user!

    # Issue a new token with fresh expiration
    new_token = issue_user_jwt(current_user)

    render json: {
      user_token: new_token,
      email: current_user.email,
      onboarding_completed: current_user.onboarding_completed,
      email_enabled: EmailConfig.enabled?
    }
  end
end
