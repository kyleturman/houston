# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notes API', type: :request do
  include_context 'authenticated user with goal'

  let(:auth_token_headers) { user_jwt_headers_for(user) }
  let(:other_goal) { Goal.create!(user: user, title: 'Other Goal', description: 'Another goal', status: :working) }

  describe 'POST /api/notes' do
    context 'basic note creation' do
      it 'creates a note with title and content' do
        post '/api/notes',
             params: { note: { title: 'Test Note', content: 'Test content' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json['data']['type']).to eq('note')
        expect(json['data']['attributes']['title']).to eq('Test Note')
        expect(json['data']['attributes']['content']).to eq('Test content')
        expect(json['data']['attributes']['source']).to eq('user')
      end

      it 'creates a note without title' do
        post '/api/notes',
             params: { note: { content: 'Just content' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        expect(json['data']['attributes']['title']).to be_nil
        expect(json['data']['attributes']['content']).to eq('Just content')
      end

      it 'requires content' do
        post '/api/notes',
             params: { note: { title: 'No content' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['errors']).to include("Content can't be blank")
      end
    end

    context 'note creation with goal context' do
      it 'creates a note associated with a goal when goal_id is provided' do
        post "/api/goals/#{goal.id}/notes",
             params: { note: { content: 'Goal-specific note' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        note = Note.find(json['data']['id'])
        expect(note.goal_id).to eq(goal.id)
      end

      it 'creates a note with explicit goal_id parameter' do
        post '/api/notes',
             params: { note: { content: 'Test content', goal_id: goal.id } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.goal_id).to eq(goal.id)
      end

      it 'serializes goal_id as string (JSON:API best practice)' do
        post '/api/notes',
             params: { note: { content: 'Test content', goal_id: goal.id } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)

        # goal_id should be a string in JSON response (for mobile client compatibility)
        goal_id_value = json['data']['attributes']['goal_id']
        expect(goal_id_value).to be_a(String)
        expect(goal_id_value).to eq(goal.id.to_s)
      end
    end

    context 'automatic goal assignment with LLM', :slow do
      before do
        # Set up goals with distinct descriptions
        # Using :waiting status to test that it includes both working and waiting goals
        goal.update!(
          status: :waiting,
          description: 'Learn Ruby on Rails and build web applications'
        )
        other_goal.update!(
          status: :working,
          description: 'Study machine learning and AI concepts'
        )
      end

      it 'automatically assigns a goal when note content matches a goal' do
        # Mock the LLM service to return the goal ID
        allow(Llms::Service).to receive(:call).and_return({
          content: [{ type: :text, text: goal.id.to_s }],
          usage: { prompt_tokens: 50, completion_tokens: 10 }
        })

        post '/api/notes',
             params: { note: { content: 'Today I learned about Rails routing and controllers' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.goal_id).to eq(goal.id)
      end

      it 'does not assign a goal when LLM returns none' do
        # Mock the LLM service to return 'none'
        allow(Llms::Service).to receive(:call).and_return({
          content: [{ type: :text, text: 'none' }],
          usage: { prompt_tokens: 50, completion_tokens: 10 }
        })

        post '/api/notes',
             params: { note: { content: 'Random unrelated thought' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.goal_id).to be_nil
      end

      it 'handles LLM errors gracefully' do
        # Mock the LLM service to raise an error
        allow(Llms::Service).to receive(:call).and_raise(StandardError.new('LLM error'))

        post '/api/notes',
             params: { note: { content: 'Test content' } },
             headers: auth_token_headers,
             as: :json

        # Note should still be created, just without goal assignment
        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.goal_id).to be_nil
      end
    end

    context 'URL processing with two-phase async', :slow do
      it 'detects URL, fetches quick metadata, queues background job' do
        # Mock quick metadata fetch (Phase 1)
        mock_browser = instance_double(Ferrum::Browser)
        allow(Ferrum::Browser).to receive(:new).and_return(mock_browser)

        allow(mock_browser).to receive(:goto)
        allow(mock_browser).to receive_message_chain(:network, :wait_for_idle)
        allow(mock_browser).to receive_message_chain(:at_css, :text).and_return('Example Website')
        allow(mock_browser).to receive(:title).and_return('Example Website')
        allow(mock_browser).to receive_message_chain(:at_css, :attribute).and_return('Example description')
        allow(mock_browser).to receive(:quit)

        # Mock goal assignment
        allow(Llms::Service).to receive(:call).and_return({
          content: [{ type: :text, text: goal.id.to_s }],
          usage: { prompt_tokens: 50, completion_tokens: 10 }
        })

        # Expect background job to be queued
        expect(ProcessUrlNoteJob).to receive(:perform_later)

        post '/api/notes',
             params: { note: { content: 'https://example.com' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        note = Note.find(json['data']['id'])

        # Verify quick metadata was fetched
        expect(note.title).to eq('Example Website')
        expect(note.content).to be_nil # URL removed, no commentary
        expect(note.metadata['source_url']).to eq('https://example.com')
        expect(note.metadata['processing_state']).to eq('pending')
        expect(note.metadata['seo']).to be_present
        expect(note.goal_id).to eq(goal.id) # Assigned based on SEO
      end

      it 'extracts user commentary and removes URL from content' do
        mock_browser = instance_double(Ferrum::Browser)
        allow(Ferrum::Browser).to receive(:new).and_return(mock_browser)
        allow(mock_browser).to receive(:goto)
        allow(mock_browser).to receive_message_chain(:network, :wait_for_idle)
        allow(mock_browser).to receive_message_chain(:at_css, :text).and_return('Example')
        allow(mock_browser).to receive(:title).and_return('Example')
        allow(mock_browser).to receive_message_chain(:at_css, :attribute).and_return('Description')
        allow(mock_browser).to receive(:quit)

        allow(Llms::Service).to receive(:call).and_return({
          content: [{ type: :text, text: 'none' }],
          usage: { prompt_tokens: 50, completion_tokens: 10 }
        })

        expect(ProcessUrlNoteJob).to receive(:perform_later)

        post '/api/notes',
             params: { note: { content: 'Check this out: https://example.com - very cool!' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])

        # URL removed, commentary preserved
        expect(note.content).to eq('Check this out: - very cool!')
        expect(note.metadata['source_url']).to eq('https://example.com')
      end

      it 'handles metadata fetch timeout gracefully' do
        # Mock timeout
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect(ProcessUrlNoteJob).to receive(:perform_later)

        post '/api/notes',
             params: { note: { content: 'https://slow-site.com' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])

        # Note created without metadata, queued for async processing
        expect(note.content).to be_nil
        expect(note.metadata['source_url']).to eq('https://slow-site.com')
        expect(note.metadata['processing_state']).to eq('pending')
        expect(note.goal_id).to be_nil # No goal assignment on timeout
      end

      it 'handles metadata fetch errors gracefully' do
        allow(Ferrum::Browser).to receive(:new).and_raise(StandardError.new('Browser error'))

        expect(ProcessUrlNoteJob).to receive(:perform_later)

        post '/api/notes',
             params: { note: { content: 'https://broken-url.com' } },
             headers: auth_token_headers,
             as: :json

        # Note created with minimal data, queued for async retry
        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.metadata['source_url']).to eq('https://broken-url.com')
        expect(note.metadata['processing_state']).to eq('pending')
      end

      it 'does not process non-URL content' do
        allow(Ferrum::Browser).to receive(:new).and_call_original

        post '/api/notes',
             params: { note: { content: 'This is just regular text without URLs' } },
             headers: auth_token_headers,
             as: :json

        expect(response).to have_http_status(:created)
        note = Note.find(JSON.parse(response.body)['data']['id'])
        expect(note.content).to eq('This is just regular text without URLs')
        expect(note.metadata).to be_blank

        # Verify Ferrum was not called
        expect(Ferrum::Browser).not_to have_received(:new)
      end
    end
  end

  describe 'GET /api/notes' do
    let!(:note1) { create(:note, user: user, title: 'Note 1', created_at: 2.days.ago) }
    let!(:note2) { create(:note, user: user, title: 'Note 2', created_at: 1.day.ago) }
    let!(:note3) { create(:note, user: user, title: 'Note 3', goal: goal, created_at: 3.days.ago) }

    it 'returns all notes for the user ordered by most recent' do
      get '/api/notes',
          headers: auth_token_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['data'].length).to eq(3)
      # Verify order (most recent first)
      expect(json['data'][0]['attributes']['title']).to eq('Note 2')
      expect(json['data'][1]['attributes']['title']).to eq('Note 1')
      expect(json['data'][2]['attributes']['title']).to eq('Note 3')
    end

    it 'filters notes by goal when accessed via goal route' do
      get "/api/goals/#{goal.id}/notes",
          headers: auth_token_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['data'].length).to eq(1)
      expect(json['data'][0]['attributes']['title']).to eq('Note 3')
    end
  end

  describe 'GET /api/notes/:id' do
    let!(:note) { create(:note, user: user, title: 'Test Note', content: 'Test content') }

    it 'returns a specific note' do
      get "/api/notes/#{note.id}",
          headers: auth_token_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['data']['id']).to eq(note.id.to_s)
      expect(json['data']['attributes']['title']).to eq('Test Note')
    end
  end

  describe 'PATCH /api/notes/:id' do
    let!(:note) { create(:note, user: user, content: 'Original content', goal: goal) }

    it 'updates note content' do
      patch "/api/notes/#{note.id}",
            params: { note: { content: 'Updated content' } },
            headers: auth_token_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      note.reload
      expect(note.content).to eq('Updated content')
    end

    it 'updates note goal association' do
      patch "/api/notes/#{note.id}",
            params: { note: { goal_id: other_goal.id } },
            headers: auth_token_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      note.reload
      expect(note.goal_id).to eq(other_goal.id)
    end

    it 'prevents moving note to a goal owned by another user' do
      other_user = create(:user)
      other_user_goal = Goal.create!(user: other_user, title: 'Other User Goal', status: :working)

      patch "/api/notes/#{note.id}",
            params: { note: { goal_id: other_user_goal.id } },
            headers: auth_token_headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/notes/:id' do
    let!(:note) { create(:note, user: user, content: 'To be deleted') }

    it 'deletes a note' do
      expect {
        delete "/api/notes/#{note.id}",
               headers: auth_token_headers
      }.to change(Note, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/notes/:id/retry_processing' do
    it 'retries processing for a failed URL note' do
      note = create(:note,
        user: user,
        content: 'Check this out!',
        metadata: {
          'source_url' => 'https://example.com',
          'processing_state' => 'failed'
        }
      )

      expect(ProcessUrlNoteJob).to receive(:perform_later).with(note.id)

      post "/api/notes/#{note.id}/retry_processing",
           headers: auth_token_headers,
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      note.reload
      expect(note.metadata['processing_state']).to eq('pending')
    end

    it 'rejects retry for notes not in failed state' do
      note = create(:note,
        user: user,
        metadata: {
          'source_url' => 'https://example.com',
          'processing_state' => 'completed'
        }
      )

      post "/api/notes/#{note.id}/retry_processing",
           headers: auth_token_headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Note processing has not failed')
    end

    it 'rejects retry for notes without source_url' do
      note = create(:note,
        user: user,
        content: 'Regular note',
        metadata: { 'processing_state' => 'failed' }
      )

      post "/api/notes/#{note.id}/retry_processing",
           headers: auth_token_headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Note does not have a source URL')
    end
  end

  describe 'POST /api/notes/:id/ignore_processing' do
    it 'ignores processing failure for a URL note' do
      note = create(:note,
        user: user,
        metadata: {
          'source_url' => 'https://example.com',
          'processing_state' => 'failed'
        }
      )

      post "/api/notes/#{note.id}/ignore_processing",
           headers: auth_token_headers,
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      note.reload
      expect(note.metadata['processing_state']).to eq('ignored')
    end

    it 'rejects ignore for notes not in failed state' do
      note = create(:note,
        user: user,
        metadata: {
          'source_url' => 'https://example.com',
          'processing_state' => 'pending'
        }
      )

      post "/api/notes/#{note.id}/ignore_processing",
           headers: auth_token_headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Note processing has not failed')
    end
  end
end
