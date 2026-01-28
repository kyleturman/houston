# frozen_string_literal: true

# Shared invite token authentication logic for both iOS API and admin dashboard
module InviteTokenAuth
  extend ActiveSupport::Concern

  # Authenticate a user with an invite token
  # Returns [user, invite_token] on success, [nil, error_message] on failure
  def authenticate_invite_token(email:, token:)
    return [nil, "Email is required"] if email.blank?
    return [nil, "Invite code is required"] if token.blank?

    user = User.find_by(email: email.strip.downcase)
    return [nil, "User not found"] unless user

    # Find a valid invite token for this user
    invite_token = user.invite_tokens.find do |it|
      it.claimable? && it.valid_token?(token.strip)
    end

    return [nil, "Invalid or expired invite code"] unless invite_token

    # Mark token as used (starts 24h reuse window if first use)
    invite_token.mark_used!

    [user, invite_token]
  end

  # Same as authenticate_invite_token but requires the user to be an admin
  def authenticate_admin_invite_token(email:, token:)
    user, result = authenticate_invite_token(email: email, token: token)

    return [nil, result] unless user # result is error message

    unless user.admin?
      return [nil, "No admin account found with that email"]
    end

    [user, result] # result is invite_token
  end
end
