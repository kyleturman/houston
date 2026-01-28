# frozen_string_literal: true

module Auth
  class InviteTokensController < ApplicationController
    include DeviceRegistration
    include InviteTokenAuth

    # POST /api/auth/invite_tokens/claim
    # Params: { email: string, token: string, device_name?: string, platform?: string }
    # Note: API uses "token" param for the invite code (kept for backward compatibility)
    def claim
      email = params.require(:email).to_s
      invite_code = params.require(:token).to_s

      user, result = authenticate_invite_token(email: email, token: invite_code)

      unless user
        status = result == "User not found" ? :not_found : :unauthorized
        return render json: { error: result }, status: status
      end

      register_device_and_respond(user)
    end
  end
end
