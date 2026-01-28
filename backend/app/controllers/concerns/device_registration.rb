# frozen_string_literal: true

# Shared device registration logic for API authentication endpoints
# Used by both magic link and invite token claim flows
module DeviceRegistration
  extend ActiveSupport::Concern

  included do
    include JwtAuth
    include UserJwt
  end

  # Register a new device for a user and render the auth response
  # @param user [User] The authenticated user
  # @return [void] Renders JSON response
  def register_device_and_respond(user)
    device = build_device(user)
    raw_device_token = device.set_token!

    if device.save
      render json: auth_response(user, device, raw_device_token), status: :created
    else
      render json: { error: device.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def build_device(user)
    name = params[:device_name].presence || "iOS Device"
    platform = params[:platform].presence || "ios"
    user.devices.build(name: name, platform: platform, last_used_at: Time.current)
  end

  def auth_response(user, device, raw_device_token)
    {
      server: server_public_url,
      server_name: server_display_name,
      device_token: raw_device_token,
      user_token: issue_user_jwt(user),
      device_id: device.id,
      user_id: user.id,
      onboarding_completed: user.onboarding_completed,
      email_enabled: EmailConfig.enabled?
    }
  end
end
