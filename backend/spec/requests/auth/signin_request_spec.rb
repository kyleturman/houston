# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::SigninRequest', type: :request do
  describe 'POST /api/auth/request_signin' do
    let(:user) { create(:user, email: 'test@example.com') }

    before do
      # Clear rate limit keys before each test
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      redis.del("auth:rate_limit:ip:127.0.0.1")
      redis.del("auth:rate_limit:email:test@example.com")
      redis.del("auth:rate_limit:email:nobody@example.com")
      redis.close
    end

    it 'returns success for existing user' do
      expect_any_instance_of(Auth::SigninRequestController).to receive(:send_magic_link).with(user, context: 'app').and_return(true)

      post '/api/auth/request_signin', params: { email: user.email }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['message']).to include('sign-in link')
    end

    it 'returns success for non-existent user to prevent enumeration' do
      post '/api/auth/request_signin', params: { email: 'nobody@example.com' }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end

    it 'rate limits by IP' do
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      # Set IP limit to just under threshold
      redis.set("auth:rate_limit:ip:127.0.0.1", 20)
      redis.expire("auth:rate_limit:ip:127.0.0.1", 900)
      redis.close

      post '/api/auth/request_signin', params: { email: user.email }

      expect(response).to have_http_status(:too_many_requests)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Too many requests')
      expect(json['retry_after']).to be_present
    end

    it 'rate limits by email' do
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      # Set email limit to threshold
      redis.set("auth:rate_limit:email:test@example.com", 10)
      redis.expire("auth:rate_limit:email:test@example.com", 900)
      redis.close

      post '/api/auth/request_signin', params: { email: user.email }

      expect(response).to have_http_status(:too_many_requests)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Too many requests for this email')
    end

    it 'normalizes email to lowercase' do
      expect_any_instance_of(Auth::SigninRequestController).to receive(:send_magic_link).with(user, context: 'app').and_return(true)

      post '/api/auth/request_signin', params: { email: 'TEST@EXAMPLE.COM' }

      expect(response).to have_http_status(:ok)
    end

    it 'requires email parameter' do
      post '/api/auth/request_signin', params: {}

      expect(response).to have_http_status(:bad_request)
    end

    it 'does not send link to inactive users' do
      inactive_user = create(:user, email: 'inactive@example.com', active: false)
      expect_any_instance_of(Auth::SigninRequestController).not_to receive(:send_magic_link)

      post '/api/auth/request_signin', params: { email: inactive_user.email }

      # Still returns success to prevent enumeration
      expect(response).to have_http_status(:ok)
    end
  end
end
