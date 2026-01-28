# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::TokenTracker do
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')) }

  before do
    # Clean up Redis before each test
    redis.flushdb
  end

  after do
    redis.close
  end

  describe '.mark_used' do
    it 'marks a token as used' do
      jti = 'test-jti-123'
      described_class.mark_used(jti)

      expect(described_class.used?(jti)).to be true
    end

    it 'sets TTL on the token' do
      jti = 'test-jti-456'
      described_class.mark_used(jti, ttl: 60)

      key = "auth:used_token:#{jti}"
      ttl = redis.ttl(key)
      expect(ttl).to be > 0
      expect(ttl).to be <= 60
    end

    it 'handles nil jti gracefully' do
      expect { described_class.mark_used(nil) }.not_to raise_error
      expect(described_class.used?(nil)).to be false
    end

    it 'expires after TTL' do
      jti = 'test-jti-789'
      described_class.mark_used(jti, ttl: 1)

      expect(described_class.used?(jti)).to be true

      # Wait for expiry
      sleep 1.1

      expect(described_class.used?(jti)).to be false
    end
  end

  describe '.used?' do
    it 'returns false for unused tokens' do
      expect(described_class.used?('unused-token')).to be false
    end

    it 'returns true for used tokens' do
      jti = 'used-token'
      described_class.mark_used(jti)

      expect(described_class.used?(jti)).to be true
    end

    it 'handles nil jti gracefully' do
      expect(described_class.used?(nil)).to be false
    end

    it 'handles empty string gracefully' do
      expect(described_class.used?('')).to be false
    end
  end

  describe 'Redis error handling' do
    it 'handles Redis errors when marking used' do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      expect { described_class.mark_used('test-jti') }.not_to raise_error
    end

    it 'fails open when checking if used and Redis is unavailable' do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      result = described_class.used?('test-jti')
      expect(result).to be false
    end
  end
end
