# frozen_string_literal: true

module Auth
  class RateLimiter
    # Rate limiting for authentication attempts to prevent abuse
    # Uses Redis to track attempts with automatic expiry

    EMAIL_LIMIT = 10      # Max attempts per email
    EMAIL_WINDOW = 900    # 15 minutes in seconds
    IP_LIMIT = 20         # Max attempts per IP
    IP_WINDOW = 900       # 15 minutes in seconds

    class << self
      # Check if email-based rate limit is exceeded
      # Returns { allowed: true/false, retry_after: seconds }
      def check_email_limit(email)
        key = "auth:rate_limit:email:#{email.to_s.downcase}"
        check_limit(key, EMAIL_LIMIT, EMAIL_WINDOW)
      end

      # Check if IP-based rate limit is exceeded
      # Returns { allowed: true/false, retry_after: seconds }
      def check_ip_limit(ip)
        key = "auth:rate_limit:ip:#{ip}"
        check_limit(key, IP_LIMIT, IP_WINDOW)
      end

      private

      def check_limit(key, max_attempts, window)
        redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

        count = redis.get(key).to_i

        if count >= max_attempts
          ttl = redis.ttl(key)
          return { allowed: false, retry_after: ttl > 0 ? ttl : window }
        end

        # Increment counter and set expiry
        ttl_before = redis.ttl(key)
        redis.multi do |r|
          r.incr(key)
          r.expire(key, window) if ttl_before <= 0
        end

        { allowed: true, retry_after: 0 }
      rescue Redis::BaseError => e
        Rails.logger.error("[RateLimiter] Redis error: #{e.message}")
        # Fail closed on Redis errors - block the request for security
        # This prevents bypassing rate limits when Redis is unavailable
        { allowed: false, retry_after: 60 }
      ensure
        redis&.close
      end
    end
  end
end
