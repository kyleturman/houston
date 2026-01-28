# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::RateLimiter do
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')) }

  before do
    # Clean up Redis before each test
    redis.flushdb
  end

  after do
    redis.close
  end

  describe '.check_email_limit' do
    it 'allows requests under the limit' do
      result = described_class.check_email_limit('test@example.com')
      expect(result[:allowed]).to be true
      expect(result[:retry_after]).to eq 0
    end

    it 'blocks requests after exceeding limit' do
      email = 'test@example.com'

      # Make 10 requests (at limit)
      10.times { described_class.check_email_limit(email) }

      # 11th request should be blocked
      result = described_class.check_email_limit(email)
      expect(result[:allowed]).to be false
      expect(result[:retry_after]).to be > 0
    end

    it 'is case insensitive' do
      email = 'Test@Example.COM'

      10.times { described_class.check_email_limit(email) }

      # Different case should still be blocked
      result = described_class.check_email_limit('test@example.com')
      expect(result[:allowed]).to be false
    end
  end

  describe '.check_ip_limit' do
    it 'allows requests under the limit' do
      result = described_class.check_ip_limit('192.168.1.1')
      expect(result[:allowed]).to be true
      expect(result[:retry_after]).to eq 0
    end

    it 'blocks requests after exceeding limit' do
      ip = '192.168.1.1'

      # Make 20 requests (at limit - IP_LIMIT is 20)
      20.times { described_class.check_ip_limit(ip) }

      # 21st request should be blocked
      result = described_class.check_ip_limit(ip)
      expect(result[:allowed]).to be false
      expect(result[:retry_after]).to be > 0
    end

    it 'different IPs have separate limits' do
      20.times { described_class.check_ip_limit('192.168.1.1') }

      # Different IP should still be allowed
      result = described_class.check_ip_limit('192.168.1.2')
      expect(result[:allowed]).to be true
    end
  end

  describe 'Redis error handling' do
    it 'fails closed when Redis is unavailable (security measure)' do
      # Stub Redis to raise an error
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      result = described_class.check_email_limit('test@example.com')
      # Fails closed - blocks requests when Redis is down to prevent rate limit bypass
      expect(result[:allowed]).to be false
      expect(result[:retry_after]).to eq 60
    end
  end
end
