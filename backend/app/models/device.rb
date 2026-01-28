# frozen_string_literal: true

class Device < ApplicationRecord
  belongs_to :user, optional: true
  validates :name, presence: true
  validates :platform, presence: true
  validates :token_digest, presence: true
  validates :token_id, presence: true, uniqueness: true

  # Generates a new random token, stores its BCrypt digest, and returns the raw token
  def set_token!
    token_id = SecureRandom.hex(8) # short identifier used for lookup
    secret = SecureRandom.hex(32)  # secret part stored only as digest
    self.token_id = token_id
    self.token_digest = BCrypt::Password.create(secret)
    composite = "#{token_id}.#{secret}"
    @raw_token = composite
    composite
  end

  # Verifies a raw token against the stored digest
  def valid_token?(raw)
    return false if token_digest.blank? || raw.blank?
    _id, secret = raw.to_s.split('.', 2)
    return false if secret.blank?
    BCrypt::Password.new(token_digest) == secret
  rescue BCrypt::Errors::InvalidHash
    false
  end
end
