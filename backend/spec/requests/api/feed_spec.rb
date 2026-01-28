# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feed API', type: :request do
  include_context 'authenticated user'

  # Feed API uses JWT authentication, not device bearer tokens
  let(:auth_headers_jwt) { user_jwt_headers_for(user) }
  let(:user_agent) { user.user_agent || create(:user_agent, user: user) }

  describe 'GET /api/feed/current' do
    it 'returns today\'s feed items' do
      # Create a note from today
      note = user.notes.create!(
        content: 'Test note',
        title: 'Note Title',
        source: :agent
      )

      # Create an insight from today
      insight = create(:feed_insight,
        user: user,
        user_agent: user_agent,
        insight_type: :reflection,
        metadata: { 'prompt' => 'How are you doing?' }
      )

      get '/api/feed/current', headers: auth_headers_jwt

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to have_key('date')
      expect(json).to have_key('items')
      expect(json['items'].length).to eq(2)
    end

    it 'only returns today\'s items' do
      # Create old note
      old_note = user.notes.create!(
        content: 'Old note',
        source: :agent,
        created_at: 2.days.ago
      )

      # Create today's note
      today_note = user.notes.create!(
        content: 'Today note',
        source: :agent
      )

      get '/api/feed/current', headers: auth_headers_jwt

      json = JSON.parse(response.body)
      expect(json['items'].length).to eq(1)
      expect(json['items'].first['id']).to eq(today_note.id.to_s)
    end

    it 'requires authentication' do
      get '/api/feed/current'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/feed/history' do
    it 'returns feed items for a specific date' do
      # Create items from 2 days ago
      old_date = 2.days.ago
      old_note = user.notes.create!(content: 'Old note', source: :agent, created_at: old_date)
      old_insight = create(:feed_insight,
        user: user,
        user_agent: user_agent,
        insight_type: :reflection,
        metadata: { 'prompt' => 'Old reflection' },
        created_at: old_date
      )

      # Create items from today
      user.notes.create!(content: 'Today note', source: :agent)

      date = 2.days.ago.to_date
      get "/api/feed/history?date=#{date.iso8601}", headers: auth_headers_jwt

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['date']).to eq(date.beginning_of_day.to_time.iso8601)
      expect(json['items'].length).to eq(2)
    end

    it 'defaults to today when no date provided' do
      user.notes.create!(content: 'Today note')

      get '/api/feed/history', headers: auth_headers_jwt

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['date']).to eq(Date.current.beginning_of_day.to_time.iso8601)
    end

    it 'returns error for invalid date' do
      get '/api/feed/history?date=invalid', headers: auth_headers_jwt

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['error']).to include('Invalid date')
    end

    it 'requires authentication' do
      get '/api/feed/history'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
