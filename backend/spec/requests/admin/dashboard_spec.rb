# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Dashboard', type: :request do
  let(:admin_user) { create(:user, role: 'admin') }

  before(:each) do
    ActionMailer::Base.deliveries.clear
    # Stub admin authentication
    allow_any_instance_of(Admin::BaseController).to receive(:require_admin).and_return(true)
    allow_any_instance_of(Admin::BaseController).to receive(:current_user).and_return(admin_user)
  end

  describe 'POST /admin/send_link' do
    let(:user) { create(:user, email: 'test@example.com') }

    context 'with valid user_id' do
      before do
        allow_any_instance_of(Admin::DashboardController).to receive(:send_magic_link).and_return(true)
      end

      it 'sends magic link and returns success JSON' do
        post '/admin/send_link', params: { user_id: user.id }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:message]).to include('Magic link sent')
      end
    end

    context 'with invalid user_id' do
      it 'returns not found error' do
        post '/admin/send_link', params: { user_id: 99999 }

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
        expect(json_response[:message]).to include('User not found')
      end
    end

    context 'without user_id' do
      it 'returns bad request error' do
        post '/admin/send_link'

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
        expect(json_response[:message]).to include('User ID is required')
      end
    end

    context 'when email sending fails' do
      before do
        allow_any_instance_of(Admin::DashboardController).to receive(:send_magic_link).and_return(false)
      end

      it 'returns internal server error' do
        post '/admin/send_link', params: { user_id: user.id }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
        expect(json_response[:message]).to include('Failed to send magic link')
      end
    end
  end

  describe 'POST /admin/create_user' do
    before do
      allow_any_instance_of(Admin::DashboardController).to receive(:send_magic_link).and_return(true)
    end

    context 'with new user' do
      it 'creates user and returns success JSON' do
        expect {
          post '/admin/create_user', params: { email: 'newuser@example.com' }
        }.to change { User.count }.by(1)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:message]).to include('created')
      end
    end

    context 'with existing user' do
      let!(:existing_user) { create(:user, email: 'existing@example.com') }

      it 'does not create duplicate and sends magic link' do
        expect {
          post '/admin/create_user', params: { email: 'existing@example.com' }
        }.not_to change { User.count }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:message]).to include('already exists')
        expect(json_response[:message]).to include('Magic link sent')
      end
    end
  end

  describe 'POST /admin/create_user_with_token' do
    context 'with new user' do
      it 'creates user, generates invite token, and returns invite_link' do
        expect {
          post '/admin/create_user_with_token', params: { email: 'newuser@example.com' }
        }.to change { User.count }.by(1)
          .and change { InviteToken.count }.by(1)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:token]).to be_present
        expect(json_response[:invite_link]).to be_present
        expect(json_response[:invite_link]).to include('heyhouston://signin')
        expect(json_response[:invite_link]).to include('type=invite')
        expect(json_response[:invite_link]).to include('newuser%40example.com')
        expect(json_response[:message]).to include('created')
      end
    end

    context 'with existing user' do
      let!(:existing_user) { create(:user, email: 'existing@example.com') }

      it 'generates invite token for existing user and returns invite_link' do
        expect {
          post '/admin/create_user_with_token', params: { email: 'existing@example.com' }
        }.not_to change { User.count }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:invite_link]).to include('type=invite')
        expect(json_response[:message]).to include('already exists')
      end
    end

    context 'without email' do
      it 'returns bad request error' do
        post '/admin/create_user_with_token'

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
      end
    end
  end

  describe 'POST /admin/create_invite_token' do
    let(:user) { create(:user, email: 'test@example.com') }

    context 'with valid user_id' do
      it 'creates invite token and returns invite_link' do
        expect {
          post '/admin/create_invite_token', params: { user_id: user.id, expires_in: '7' }
        }.to change { InviteToken.count }.by(1)

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be true
        expect(json_response[:token]).to be_present
        expect(json_response[:invite_link]).to be_present
        expect(json_response[:invite_link]).to include('heyhouston://signin')
        expect(json_response[:invite_link]).to include('type=invite')
        expect(json_response[:invite_link]).to include('test%40example.com')
        expect(json_response[:expires_at]).to be_present
      end

      it 'creates non-expiring token when expires_in is never' do
        post '/admin/create_invite_token', params: { user_id: user.id, expires_in: 'never' }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:expires_at]).to be_nil
        expect(json_response[:invite_link]).to include('type=invite')
      end
    end

    context 'with invalid user_id' do
      it 'returns not found error' do
        post '/admin/create_invite_token', params: { user_id: 99999 }

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
      end
    end

    context 'without user_id' do
      it 'returns bad request error' do
        post '/admin/create_invite_token'

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:success]).to be false
      end
    end
  end
end
