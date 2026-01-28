# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::Capabilities', type: :request do
  describe 'GET /api/capabilities' do
    it 'returns server capabilities without authentication' do
      get '/api/capabilities'

      expect(response).to have_http_status(:ok)
      expect(json_response).to have_key(:sse_enabled)
      expect(json_response).to have_key(:version)
    end

    it 'returns SSE enabled' do
      get '/api/capabilities'

      expect(response).to have_http_status(:ok)
      expect(json_response[:sse_enabled]).to be true
    end

    it 'returns correct version' do
      get '/api/capabilities'

      expect(response).to have_http_status(:ok)
      expect(json_response[:version]).to eq('1.0.0')
    end
  end

  private

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end
