# frozen_string_literal: true

class InviteToken < ApplicationRecord
  # Character set for token generation: A-Z a-z 0-9 and symbols
  TOKEN_CHARSET = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + %w[! @ # $ % ^ & * - _]
  TOKEN_CHUNK_SIZE = 6
  TOKEN_CHUNK_COUNT = 3
  REUSE_WINDOW_HOURS = 24

  belongs_to :user

  validates :token_digest, presence: true

  # Generate a new token, store its BCrypt digest, and return the raw token
  # Format: XXXXXX-XXXXXX-XXXXXX (3 chunks of 6 alphanumeric+symbol characters)
  def set_token!
    chunks = TOKEN_CHUNK_COUNT.times.map do
      TOKEN_CHUNK_SIZE.times.map { TOKEN_CHARSET.sample }.join
    end
    raw_token = chunks.join('-')
    self.token_digest = BCrypt::Password.create(raw_token)
    @raw_token = raw_token
    raw_token
  end

  # Verify a raw token against the stored digest
  def valid_token?(raw)
    return false if token_digest.blank? || raw.blank?
    BCrypt::Password.new(token_digest) == raw
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Check if this token can be used for claiming
  def claimable?
    return false if revoked?
    return false if expired?
    return false if locked?
    true
  end

  # Token has been manually revoked
  def revoked?
    revoked_at.present?
  end

  # Token has passed its expiration date
  def expired?
    expires_at.present? && Time.current > expires_at
  end

  # Token has been used and the 24h reuse window has passed
  def locked?
    first_used_at.present? && Time.current > (first_used_at + REUSE_WINDOW_HOURS.hours)
  end

  # Token has been used at least once
  def used?
    first_used_at.present?
  end

  # Mark the token as used (only sets first_used_at if not already set)
  def mark_used!
    return if first_used_at.present?
    update!(first_used_at: Time.current)
  end

  # Revoke the token
  def revoke!
    update!(revoked_at: Time.current)
  end

  # Human-readable status
  def status
    return 'revoked' if revoked?
    return 'expired' if expired?
    return 'locked' if locked?
    return 'used' if used?
    'active'
  end

  # Scope for active (claimable) tokens
  scope :active, -> {
    where(revoked_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.current)
      .where('first_used_at IS NULL OR first_used_at > ?', REUSE_WINDOW_HOURS.hours.ago)
  }

  # Scope for tokens that are no longer usable
  scope :inactive, -> {
    where.not(id: active)
  }

  # Find an active token by raw token value (checks BCrypt hash)
  # Returns the token if found and valid, nil otherwise
  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    active.find_each do |token|
      return token if token.valid_token?(raw_token)
    end
    nil
  end
end
