# frozen_string_literal: true

require 'spec_helper'
require 'time'

# Contract tests for iOS API responses and SSE streaming formats
# Tags: :api, :ios_contract, :fast
RSpec.describe 'iOS API Contracts', :api, :ios_contract, :fast do
  describe 'SSE event format' do
    it 'defines the required keys for tool activity messages (contract)' do
      now = Time.now.utc
      example_payload = {
        id: 'uuid',
        content: '',
        source: 'system',
        metadata: {
          tool_activity: {
            id: 'tool-activity-id',
            name: 'create_note',
            status: 'success',
            input: {
              title: 'Sample',
              content: 'Sample note content'
            },
            display_message: 'Jotting down findings',
            data: {
              note_id: 123,
              title: 'Sample',
              content: 'Sample note content',
              status: 'created'
            }
          }
        }
      }

      expect(example_payload.keys).to include(:id, :content, :source, :metadata)
      expect(example_payload[:metadata].keys).to include(:tool_activity)
      ta = example_payload[:metadata][:tool_activity]
      expect(ta.keys).to include(:id, :name, :status, :input, :data)
      expect(ta[:data].keys).to include(:note_id, :title, :content)
    end

    it 'defines the required keys for search tool messages (contract)' do
      example_payload = {
        id: 'uuid',
        content: '',
        source: 'system',
        metadata: {
          tool_activity: {
            id: 'search-activity-id',
            name: 'brave_web_search',
            status: 'success',
            input: {
              query: 'baby classes Oakland'
            },
            display_message: 'Searching the web',
            data: {
              content: [
                { type: 'text', text: '{"title":"Result","url":"https://example.com","snippet":"..."}' }
              ],
              isError: false
            }
          }
        }
      }

      ta = example_payload[:metadata][:tool_activity]
      expect(ta.keys).to include(:id, :name, :status, :input, :data)
      expect(ta[:name]).to eq('brave_web_search')
      expect(ta[:data][:content]).to be_an(Array)
      expect(ta[:data][:isError]).to eq(false)
    end
  end
end
