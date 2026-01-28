# frozen_string_literal: true

# JWT-based authentication for pairing and magic sign-in tokens
module JwtAuth
  extend ActiveSupport::Concern

  class JwtError < StandardError; end

  included do
    include ServerConfig
  end

  def pairing_jwt_secret
    secret = ENV['PAIRING_JWT_SECRET'].presence ||
             Rails.application.credentials.dig(:pairing_jwt_secret)

    # In production, require explicit JWT secret configuration
    if secret.blank? && Rails.env.production?
      Rails.logger.error("[JwtAuth] PAIRING_JWT_SECRET not configured in production!")
      raise JwtError, 'JWT configuration error'
    end

    # Fall back to secret_key_base only in development/test
    secret.presence || Rails.application.secret_key_base
  end

  def issue_pairing_token(payload = {}, ttl: default_pairing_ttl)
    now = Time.now.to_i
    exp = now + ttl
    body = payload.merge({ iat: now, exp: exp, typ: 'pairing' })
    JWT.encode(body, pairing_jwt_secret, 'HS256')
  end

  def decode_pairing_token(token)
    decoded, = JWT.decode(token, pairing_jwt_secret, true, { algorithm: 'HS256' })
    raise JwtError, 'Invalid token type' unless decoded['typ'] == 'pairing'
    decoded
  rescue JWT::DecodeError => e
    raise JwtError, e.message
  end

  private

  def default_pairing_ttl
    # default 10 minutes
    (ENV['PAIRING_TOKEN_TTL'].presence || '600').to_i
  end

  public

  # Magic sign-in tokens are short-lived JWTs bound to an email address.
  # context: 'app' for mobile app deep link, 'admin' for admin dashboard
  def issue_signin_token(email, ttl: default_signin_ttl, context: 'app')
    now = Time.now.to_i
    exp = now + ttl
    body = { iat: now, exp: exp, typ: 'signin', sub: email.to_s.downcase, jti: SecureRandom.uuid, ctx: context }
    JWT.encode(body, pairing_jwt_secret, 'HS256')
  end

  def decode_signin_token(token)
    decoded, = JWT.decode(token, pairing_jwt_secret, true, { algorithm: 'HS256' })
    raise JwtError, 'Invalid token type' unless decoded['typ'] == 'signin'
    decoded
  rescue JWT::DecodeError => e
    raise JwtError, e.message
  end

  private

  def default_signin_ttl
    # default 15 minutes
    (ENV['SIGNIN_TOKEN_TTL'].presence || '900').to_i
  end
end
