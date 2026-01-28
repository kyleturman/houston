# frozen_string_literal: true

module DeviceAuth
  extend ActiveSupport::Concern

  included do
    attr_reader :current_device
  end

  DEVICE_AUTH_SCHEME = 'Device'

  def authenticate_device!
    raw = extract_device_token
    return render json: { error: 'Missing device token' }, status: :unauthorized if raw.blank?

    token_id, _secret = raw.split('.', 2)
    return render json: { error: 'Invalid device token format' }, status: :unauthorized if token_id.blank?

    device = Device.find_by(token_id: token_id)
    if device.nil?
      # Specific error for revoked/deleted devices so iOS can detect and clear cache
      return render json: { error: 'device_token_revoked', message: 'This device token has been revoked. Please sign in again.' }, status: :unauthorized
    end

    unless device.valid_token?(raw)
      return render json: { error: 'Invalid device token' }, status: :unauthorized
    end

    # Track last usage for session management
    device.update_column(:last_used_at, Time.current)

    @current_device = device
  end

  private

  def extract_device_token
    auth = request.headers['Authorization'].to_s
    return nil if auth.blank?
    scheme, value = auth.split(' ', 2)
    return nil unless scheme == DEVICE_AUTH_SCHEME && value.present?
    value.strip
  end
end
