# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::InviteTokens', type: :request do
  describe 'POST /api/auth/invite_tokens/claim' do
    let(:user) { create(:user, email: 'test@example.com') }

    it 'returns device and user tokens for valid invite' do
      invite_token = create(:invite_token, user: user)
      raw_token = invite_token.instance_variable_get(:@raw_token)

      post '/api/auth/invite_tokens/claim', params: {
        email: user.email,
        token: raw_token,
        device_name: 'Test iPhone'
      }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['device_token']).to be_present
      expect(json['user_token']).to be_present
    end

    it 'rejects invalid/expired/revoked tokens' do
      # Wrong token
      create(:invite_token, user: user)
      post '/api/auth/invite_tokens/claim', params: { email: user.email, token: 'wrong' }
      expect(response).to have_http_status(:unauthorized)

      # Expired
      expired = create(:invite_token, :expired, user: user)
      post '/api/auth/invite_tokens/claim', params: { email: user.email, token: expired.instance_variable_get(:@raw_token) }
      expect(response).to have_http_status(:unauthorized)

      # Revoked
      revoked = create(:invite_token, :revoked, user: user)
      post '/api/auth/invite_tokens/claim', params: { email: user.email, token: revoked.instance_variable_get(:@raw_token) }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for non-existent user' do
      post '/api/auth/invite_tokens/claim', params: { email: 'nobody@example.com', token: 'any' }
      expect(response).to have_http_status(:not_found)
    end
  end
end
