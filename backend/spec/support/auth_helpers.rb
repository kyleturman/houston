# frozen_string_literal: true

# Authentication helpers for tests
# Provides utilities for creating authenticated users and devices
#
# Usage:
#   user = create(:user)
#   device = create_authenticated_device(user)
#   get '/api/endpoint', headers: auth_headers_for(device)

module AuthHelpers
  # Create an authenticated device for the user
  # Returns device with @raw_token instance variable set
  def create_authenticated_device(user)
    dev = user.devices.new(name: 'Test Device', platform: 'ios')
    token = dev.set_token!
    dev.save!
    dev.instance_variable_set(:@raw_token, token)
    dev
  end
  
  # Get authentication headers for the device (Bearer token)
  def auth_headers_for(device)
    { 'Authorization' => "Bearer #{device.instance_variable_get(:@raw_token)}" }
  end

  # Get authentication headers for user JWT
  def user_jwt_headers_for(user)
    jwt_secret = ENV.fetch('USER_JWT_SECRET') { Rails.application.secret_key_base }
    payload = { 
      sub: user.id, 
      iat: Time.now.to_i, 
      exp: Time.now.to_i + 3600, 
      typ: 'user' 
    }
    token = JWT.encode(payload, jwt_secret, 'HS256')
    { 'Authorization' => "User #{token}" }
  end

  # Quick setup: create user + device + headers in one go
  def setup_authenticated_user
    user = create(:user)
    device = create_authenticated_device(user)
    headers = auth_headers_for(device)
    { user: user, device: device, headers: headers }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
