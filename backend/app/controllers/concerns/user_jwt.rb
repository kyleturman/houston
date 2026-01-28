# frozen_string_literal: true

module UserJwt
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  class Error < StandardError; end

  def user_jwt_secret
    secret = ENV['USER_JWT_SECRET'].presence ||
             Rails.application.credentials.dig(:user_jwt_secret)

    # In production, require explicit JWT secret configuration
    if secret.blank? && Rails.env.production?
      Rails.logger.error("[UserJwt] USER_JWT_SECRET not configured in production!")
      raise Error, 'JWT configuration error'
    end

    # Fall back to secret_key_base only in development/test
    secret.presence || Rails.application.secret_key_base
  end

  def issue_user_jwt(user, ttl: default_user_ttl)
    now = Time.now.to_i
    exp = now + ttl
    payload = { sub: user.id, iat: now, exp: exp, typ: 'user' }
    JWT.encode(payload, user_jwt_secret, 'HS256')
  end

  def authenticate_user!
    raw = extract_user_token
    return render json: { error: 'Missing user token' }, status: :unauthorized if raw.blank?

    decoded, = JWT.decode(raw, user_jwt_secret, true, { algorithm: 'HS256' })
    raise Error, 'Invalid token type' unless decoded['typ'] == 'user'
    @current_user = User.find_by(id: decoded['sub'])
    return render json: { error: 'User not found' }, status: :unauthorized if @current_user.nil?

    # Set timezone from header (inferred from iOS device)
    @current_user.timezone = request.headers['X-Timezone'] if request.headers['X-Timezone'].present?
  rescue JWT::DecodeError => e
    render json: { error: e.message }, status: :unauthorized
  rescue Error => e
    render json: { error: e.message }, status: :unauthorized
  end

  private

  def default_user_ttl
    # default 90 days
    (ENV['USER_JWT_TTL'].presence || (90 * 24 * 3600).to_s).to_i
  end

  def extract_user_token
    auth = request.headers['Authorization'].to_s
    return nil if auth.blank?
    scheme, value = auth.split(' ', 2)
    return nil unless scheme == 'User' && value.present?
    value.strip
  end
end
