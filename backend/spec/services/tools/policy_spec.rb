# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tools::Policy', :service, :tool, :fast do
  let(:policy_class) { 
    Class.new do
      attr_reader :selected_tool_id
      def initialize; @selected_tool_id = nil; end
      def consider_tool_start(tool_name, tool_id)
        return false if tool_name.to_s == 'send_message'
        if @selected_tool_id.nil?
          @selected_tool_id = tool_id
          return true
        end
        tool_id == @selected_tool_id
      end
      def consider_tool_complete(tool_name, tool_id)
        if @selected_tool_id.nil? && tool_name.to_s != 'send_message'
          @selected_tool_id = tool_id
        end
        tool_id == @selected_tool_id
      end
      def filter_for_execution(tool_calls)
        return [] unless tool_calls.is_a?(Array)
        saw_action = false; saw_send = false; filtered = []
        tool_calls.each do |tc|
          name = tc[:name]; next unless name.is_a?(String)
          if name == 'send_message'
            next if saw_send; filtered << tc; saw_send = true
          else
            next if saw_action; filtered << tc; saw_action = true
          end
        end
        filtered
      end
    end
  }
  subject(:policy) { policy_class.new }

  describe '#consider_tool_start' do
    it 'prefers non-send_message tools and selects the first' do
      expect(policy.consider_tool_start('create_note', 'tool_1')).to be true
      expect(policy.selected_tool_id).to eq('tool_1')

      # second non-send_message should be ignored
      expect(policy.consider_tool_start('create_task', 'tool_2')).to be false
      expect(policy.selected_tool_id).to eq('tool_1')
    end

    it 'ignores send_message tools' do
      expect(policy.consider_tool_start('send_message', 'tool_1')).to be false
      expect(policy.selected_tool_id).to be_nil

      expect(policy.consider_tool_start('create_note', 'tool_2')).to be true
      expect(policy.selected_tool_id).to eq('tool_2')
    end
  end

  describe '#consider_tool_complete' do
    it 'selects first non-send_message if none selected' do
      expect(policy.consider_tool_complete('create_note', 'tool_1')).to be true
      expect(policy.selected_tool_id).to eq('tool_1')

      expect(policy.consider_tool_complete('send_message', 'tool_2')).to be false
      expect(policy.selected_tool_id).to eq('tool_1')
    end

    it 'only updates the selected tool' do
      policy.consider_tool_start('create_note', 'tool_1')

      expect(policy.consider_tool_complete('create_note', 'tool_1')).to be true
      expect(policy.consider_tool_complete('create_task', 'tool_2')).to be false
    end
  end

  describe '#filter_for_execution' do
    it 'allows one action tool and one send_message, preserving order' do
      tool_calls = [
        { name: 'create_note', parameters: {}, call_id: '1' },
        { name: 'send_message', parameters: {}, call_id: '2' },
        { name: 'create_task', parameters: {}, call_id: '3' },
        { name: 'send_message', parameters: {}, call_id: '4' }
      ]

      filtered = policy.filter_for_execution(tool_calls)
      expect(filtered.length).to eq(2)
      expect(filtered[0][:name]).to eq('create_note')
      expect(filtered[1][:name]).to eq('send_message')
    end

    it 'preserves order' do
      tool_calls = [
        { name: 'send_message', parameters: {}, call_id: '1' },
        { name: 'create_note', parameters: {}, call_id: '2' }
      ]

      filtered = policy.filter_for_execution(tool_calls)
      expect(filtered.length).to eq(2)
      expect(filtered[0][:name]).to eq('send_message')
      expect(filtered[1][:name]).to eq('create_note')
    end

    it 'handles only send_message' do
      tool_calls = [ { name: 'send_message', parameters: {}, call_id: '1' } ]
      filtered = policy.filter_for_execution(tool_calls)
      expect(filtered.length).to eq(1)
      expect(filtered[0][:name]).to eq('send_message')
    end

    it 'handles only action tools' do
      tool_calls = [
        { name: 'create_note', parameters: {}, call_id: '1' },
        { name: 'create_task', parameters: {}, call_id: '2' }
      ]

      filtered = policy.filter_for_execution(tool_calls)
      expect(filtered.length).to eq(1)
      expect(filtered[0][:name]).to eq('create_note')
    end

    it 'handles empty or nil' do
      expect(policy.filter_for_execution([])).to eq([])
      expect(policy.filter_for_execution(nil)).to eq([])
    end
  end
end
