# frozen_string_literal: true

module Auth
  class TokenTracker
    # Tracks one-time token usage to prevent replay attacks
    # Tokens are stored in Redis with TTL matching their expiry time

    class << self
      # Mark a token as used
      # @param jti [String] The JWT ID (jti claim)
      # @param ttl [Integer] Time to live in seconds (should match token expiry)
      def mark_used(jti, ttl: 900)
        return unless jti.present?

        key = token_key(jti)
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
        redis.setex(key, ttl, '1')
        Rails.logger.info("[TokenTracker] Marked token as used: #{jti}")
      rescue Redis::BaseError => e
        Rails.logger.error("[TokenTracker] Redis error marking token used: #{e.message}")
      ensure
        redis&.close
      end

      # Check if a token has already been used
      # @param jti [String] The JWT ID (jti claim)
      # @return [Boolean] true if token was already used
      def used?(jti)
        return false unless jti.present?

        key = token_key(jti)
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
        exists = redis.exists?(key)
        exists
      rescue Redis::BaseError => e
        Rails.logger.error("[TokenTracker] Redis error checking token: #{e.message}")
        # Fail open on Redis errors - assume not used
        false
      ensure
        redis&.close
      end

      private

      def token_key(jti)
        "auth:used_token:#{jti}"
      end
    end
  end
end
