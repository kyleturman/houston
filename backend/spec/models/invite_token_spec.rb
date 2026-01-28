# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InviteToken, type: :model do
  describe '#set_token!' do
    it 'generates token in correct format and validates correctly' do
      token = build(:invite_token)
      raw = token.set_token!

      # Format: 3 chunks of 6 chars separated by dashes
      expect(raw).to match(/^.{6}-.{6}-.{6}$/)
      expect(token.valid_token?(raw)).to be true
      expect(token.valid_token?('wrong-token')).to be false
    end
  end

  describe '#claimable?' do
    it 'returns true for active token, false for expired/revoked/locked' do
      active = create(:invite_token)
      expect(active.claimable?).to be true

      expired = create(:invite_token, :expired)
      expect(expired.claimable?).to be false

      revoked = create(:invite_token, :revoked)
      expect(revoked.claimable?).to be false

      locked = create(:invite_token, :locked)
      expect(locked.claimable?).to be false
    end

    it 'allows reuse within 24h window' do
      token = create(:invite_token, :used)
      expect(token.claimable?).to be true
    end
  end

  describe '#mark_used!' do
    it 'sets first_used_at only on first use' do
      token = create(:invite_token)
      expect(token.first_used_at).to be_nil

      token.mark_used!
      original_time = token.first_used_at
      expect(original_time).to be_present

      token.mark_used!
      token.reload
      expect(token.first_used_at).to eq(original_time)
    end
  end
end
