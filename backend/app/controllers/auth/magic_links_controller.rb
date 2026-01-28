# frozen_string_literal: true

module Auth
  class MagicLinksController < ApplicationController
    include DeviceRegistration

    # POST /api/auth/magic_links/claim
    # Params: { token: string, device_name?: string, platform?: string }
    def claim
      token = params.require(:token)
      begin
        decoded = decode_signin_token(token)
      rescue JwtAuth::JwtError => e
        return render json: { error: e.message }, status: :unauthorized
      end

      email = decoded["sub"].to_s
      user = User.find_by(email: email)
      return render json: { error: "User not found" }, status: :not_found unless user

      register_device_and_respond(user)
    end
  end
end
