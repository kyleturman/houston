# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Signin', type: :request do
  let(:user) { create(:user, email: "signin-test-#{SecureRandom.hex(4)}@example.com") }
  let(:redis) { Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')) }

  before(:each) do
    redis.flushdb
  end

  after(:all) do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    redis.flushdb
    redis.close
  end

  describe 'GET /auth/signin' do
    context 'with valid token' do
      it 'redirects to app with deep link' do
        # Generate a valid signin token
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        now = Time.now.to_i
        payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: SecureRandom.uuid }
        token = JWT.encode(payload, jwt_secret, 'HS256')

        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Opening App')
        expect(response.body).to include('heyhouston://signin')
      end

      it 'marks token as used' do
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        now = Time.now.to_i
        jti = SecureRandom.uuid
        payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
        token = JWT.encode(payload, jwt_secret, 'HS256')

        get "/auth/signin?token=#{token}"

        expect(Auth::TokenTracker.used?(jti)).to be true
      end
    end

    context 'with expired token' do
      before do
        # Stub email sending to ensure test doesn't depend on mailer configuration
        allow_any_instance_of(Auth::SigninController).to receive(:send_magic_link).and_return(true)
      end

      it 'shows message to check email for fresh link' do
        # Ensure user exists for this test
        user # Creates the user via let

        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        past = 2.hours.ago.to_i
        payload = { iat: past, exp: past + 900, typ: 'signin', sub: user.email, jti: SecureRandom.uuid }
        token = JWT.encode(payload, jwt_secret, 'HS256')

        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Server link expired')
        expect(response.body).to include('Check email for fresh link')
      end

      it 'respects rate limiting on expired token' do
        # Ensure user exists for this test
        user # Creates the user via let

        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        past = 2.hours.ago.to_i

        # Exhaust rate limit with different tokens each time (EMAIL_LIMIT is 10)
        10.times do
          payload = { iat: past, exp: past + 900, typ: 'signin', sub: user.email, jti: SecureRandom.uuid }
          token = JWT.encode(payload, jwt_secret, 'HS256')
          get "/auth/signin?token=#{token}"
        end

        # Next request should be rate limited
        payload = { iat: past, exp: past + 900, typ: 'signin', sub: user.email, jti: SecureRandom.uuid }
        token = JWT.encode(payload, jwt_secret, 'HS256')
        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include('Too many attempts')
      end
    end

    context 'with already used token' do
      it 'shows error message' do
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        now = Time.now.to_i
        jti = SecureRandom.uuid
        payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
        token = JWT.encode(payload, jwt_secret, 'HS256')

        # Use token once
        get "/auth/signin?token=#{token}"
        expect(response).to have_http_status(:ok)

        # Try to use again
        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('already been used')
      end
    end

    context 'with invalid token' do
      it 'shows error message' do
        get '/auth/signin?token=invalid-token'

        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('Invalid sign-in link')
      end
    end

    context 'without token parameter' do
      it 'shows error message' do
        get '/auth/signin'

        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('Missing sign-in token')
      end
    end

    context 'rate limiting' do
      it 'blocks requests after IP limit' do
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        now = Time.now.to_i

        # Make 10 requests (IP limit)
        10.times do
          jti = SecureRandom.uuid
          payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
          token = JWT.encode(payload, jwt_secret, 'HS256')
          get "/auth/signin?token=#{token}"
        end

        # 11th request should be blocked
        jti = SecureRandom.uuid
        payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
        token = JWT.encode(payload, jwt_secret, 'HS256')
        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include('Too many attempts')
      end

      it 'blocks requests after email limit' do
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        now = Time.now.to_i

        # Make 10 requests for same email (EMAIL_LIMIT is 10)
        10.times do
          jti = SecureRandom.uuid
          payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
          token = JWT.encode(payload, jwt_secret, 'HS256')
          get "/auth/signin?token=#{token}"
        end

        # 11th request should be blocked
        jti = SecureRandom.uuid
        payload = { iat: now, exp: now + 900, typ: 'signin', sub: user.email, jti: jti }
        token = JWT.encode(payload, jwt_secret, 'HS256')
        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:too_many_requests)
        expect(response.body).to include('Too many attempts')
      end
    end

    context 'with user not found (expired token)' do
      it 'shows error when user does not exist' do
        jwt_secret = ENV['PAIRING_JWT_SECRET'].presence || Rails.application.secret_key_base
        past = 2.hours.ago.to_i
        payload = { iat: past, exp: past + 900, typ: 'signin', sub: 'nonexistent@example.com', jti: SecureRandom.uuid }
        token = JWT.encode(payload, jwt_secret, 'HS256')

        get "/auth/signin?token=#{token}"

        expect(response).to have_http_status(:bad_request)
        # When user not found, shows generic invalid link message (secure - no info leakage)
        expect(response.body).to include('Sign-In Error')
      end
    end
  end
end
