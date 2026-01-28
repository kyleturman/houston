# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::Registry, '#determine_tool_status' do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }
  let(:registry) { described_class.new(user: user, goal: goal, task: nil, agentable: goal) }

  describe 'MCP tool results' do
    context 'with successful result' do
      let(:mcp_success_result) do
        {
          'content' => [
            {
              'type' => 'text',
              'text' => '{"success": true, "accounts": [{"id": "123"}]}'
            }
          ]
        }
      end

      it 'returns success' do
        status = registry.send(:determine_tool_status, mcp_success_result)
        expect(status).to eq('success')
      end
    end

    context 'with failed result' do
      let(:mcp_failure_result) do
        {
          'content' => [
            {
              'type' => 'text',
              'text' => '{"success": false, "error": "Invalid token"}'
            }
          ]
        }
      end

      it 'returns failure' do
        status = registry.send(:determine_tool_status, mcp_failure_result)
        expect(status).to eq('failure')
      end
    end

    context 'with symbol keys' do
      let(:mcp_symbol_result) do
        {
          content: [
            {
              type: 'text',
              text: '{"success": true, "data": "test"}'
            }
          ]
        }
      end

      it 'returns success' do
        status = registry.send(:determine_tool_status, mcp_symbol_result)
        expect(status).to eq('success')
      end
    end

    context 'with non-JSON text content' do
      let(:mcp_text_result) do
        {
          'content' => [
            {
              'type' => 'text',
              'text' => 'Some plain text result'
            }
          ]
        }
      end

      it 'treats as success' do
        status = registry.send(:determine_tool_status, mcp_text_result)
        expect(status).to eq('success')
      end
    end

    context 'with isError field' do
      let(:mcp_error_result) do
        {
          'isError' => true,
          'content' => 'Tool not found'
        }
      end

      it 'returns failure' do
        status = registry.send(:determine_tool_status, mcp_error_result)
        expect(status).to eq('failure')
      end
    end

    context 'with error field' do
      let(:error_result) do
        {
          'error' => 'Something went wrong'
        }
      end

      it 'returns failure' do
        status = registry.send(:determine_tool_status, error_result)
        expect(status).to eq('failure')
      end
    end
  end

  describe 'System tool results' do
    context 'with successful result' do
      let(:system_success_result) do
        {
          success: true,
          note_id: 123,
          message: 'Note created'
        }
      end

      it 'returns success' do
        status = registry.send(:determine_tool_status, system_success_result)
        expect(status).to eq('success')
      end
    end

    context 'with failed result' do
      let(:system_failure_result) do
        {
          error: 'Title required'
        }
      end

      it 'returns failure' do
        status = registry.send(:determine_tool_status, system_failure_result)
        expect(status).to eq('failure')
      end
    end

    context 'with string key success' do
      let(:string_success_result) do
        {
          'success' => true,
          'data' => 'test'
        }
      end

      it 'returns success' do
        status = registry.send(:determine_tool_status, string_success_result)
        expect(status).to eq('success')
      end
    end
  end

  describe 'Edge cases' do
    context 'with data but no explicit status' do
      let(:implicit_success_result) do
        {
          data: 'some data',
          count: 5
        }
      end

      it 'treats as success' do
        status = registry.send(:determine_tool_status, implicit_success_result)
        expect(status).to eq('success')
      end
    end

    context 'with empty hash' do
      let(:empty_result) { {} }

      it 'returns failure' do
        status = registry.send(:determine_tool_status, empty_result)
        expect(status).to eq('failure')
      end
    end
  end
end
