require 'rails_helper'

RSpec.describe 'Goals API', type: :request do
  include_context 'authenticated user with goal'
  
  let(:auth_token_headers) { user_jwt_headers_for(user) }

  describe 'PATCH /api/goals/:id' do
    context 'when updating learnings' do
      it 'formats string learnings into dictionary format' do
        patch "/api/goals/#{goal.id}",
              params: { goal: { learnings: ['Learning 1', 'Learning 2'] } },
              headers: auth_token_headers,
              as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        
        # Verify JSONAPI structure
        expect(json['data']).to be_present
        expect(json['data']['type']).to eq('goal')
        expect(json['data']['attributes']).to be_present
        
        # Verify learnings are formatted as dictionaries with content and created_at
        learnings = json['data']['attributes']['learnings']
        expect(learnings).to be_an(Array)
        expect(learnings.length).to eq(2)
        
        learnings.each do |learning|
          expect(learning).to have_key('content')
          expect(learning).to have_key('created_at')
        end
        
        expect(learnings[0]['content']).to eq('Learning 1')
        expect(learnings[1]['content']).to eq('Learning 2')
        
        # Verify goal was actually updated in database
        goal.reload
        expect(goal.learnings.length).to eq(2)
        expect(goal.learnings[0]['content']).to eq('Learning 1')
      end
    end
  end
end
