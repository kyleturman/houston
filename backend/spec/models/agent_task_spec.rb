# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentTask, type: :model do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user) }
  
  describe 'validations' do
    it 'requires title' do
      task = AgentTask.new(goal: goal, user: user, instructions: 'Test instructions')
      expect(task).not_to be_valid
      expect(task.errors[:title]).to include("can't be blank")
    end
    
    it 'requires priority' do
      task = AgentTask.new(goal: goal, user: user, title: 'Test Task', status: 'active', priority: nil)
      expect(task).not_to be_valid
      expect(task.errors[:priority]).to include("can't be blank")
    end
    
    it 'allows goal to be optional' do
      task = AgentTask.new(user: user, title: 'Test Task', priority: 'normal', status: 'active')
      expect(task).to be_valid
    end
    
    it 'requires user' do
      task = AgentTask.new(goal: goal, title: 'Test Task', priority: 'normal', status: 'active')
      expect(task).not_to be_valid
      expect(task.errors[:user]).to include('must exist')
    end
    
    it 'is valid with all required attributes' do
      task = AgentTask.new(goal: goal, user: user, title: 'Test Task', priority: 'normal', status: 'active')
      expect(task).to be_valid
    end
  end
  
  describe 'associations' do
    it 'belongs to goal' do
      expect(AgentTask.reflect_on_association(:goal).macro).to eq(:belongs_to)
    end
    
    it 'belongs to user' do
      expect(AgentTask.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
    
    it 'has many thread_messages as agentable' do
      expect(AgentTask.reflect_on_association(:thread_messages).macro).to eq(:has_many)
      expect(AgentTask.reflect_on_association(:thread_messages).options[:as]).to eq(:agentable)
    end
  end
  
  describe 'status transitions' do
    let(:task) { AgentTask.create!(title: 'Test Task', priority: 'normal', status: 'active', goal: goal, user: user) }
    
    it 'defaults to active status' do
      new_task = AgentTask.create!(goal: goal, user: user, title: 'Test', priority: 'normal')
      expect(new_task.status).to eq('active')
    end
    
    it 'can transition from active to completed' do
      task.update!(status: 'completed', result_summary: 'Task completed successfully')
      expect(task.status).to eq('completed')
      expect(task.result_summary).to eq('Task completed successfully')
    end
    
    it 'can transition from active to paused' do
      task.update!(status: 'paused', result_summary: 'Task paused by user')
      expect(task.status).to eq('paused')
      expect(task.result_summary).to eq('Task paused by user')
    end
    
    it 'allows setting result_summary when completed' do
      task.update!(status: 'completed', result_summary: 'Done')
      expect(task.status).to eq('completed')
      expect(task.result_summary).to eq('Done')
    end

    it 'updates ThreadMessage metadata when task status changes' do
      # Create a ThreadMessage that represents the task creation
      activity_id = SecureRandom.uuid
      task.update!(origin_tool_activity_id: activity_id)

      thread_message = ThreadMessage.create!(
        user: user,
        agentable: goal,
        source: :agent,
        message_type: :tool,
        tool_activity_id: activity_id,
        metadata: {
          tool_activity: {
            id: activity_id,
            name: 'create_task',
            status: 'success',
            input: { title: 'Test Task' },
            display_message: 'Creating task...',
            data: {
              task_id: task.id,
              task_title: task.title,
              task_status: 'active'
            }
          }
        }
      )

      # Complete the task (this triggers the callback)
      task.update!(status: 'completed', result_summary: 'Task completed')

      # Verify ThreadMessage metadata was updated correctly
      thread_message.reload
      tool_activity = thread_message.metadata['tool_activity']

      # task_status should be in data (standardized structure)
      expect(tool_activity['data']['task_status']).to eq('completed')

      # display_message should be cleared when task completes
      expect(tool_activity['display_message']).to be_nil

      # Verify no flattened task_status at top level
      expect(tool_activity.key?('task_status')).to be(false),
        "task_status should NOT be at top level, only in data"
    end
  end
  
  describe 'scopes' do
    let!(:active_task) { AgentTask.create!(title: 'Active Task', priority: 'normal', status: 'active', goal: goal, user: user) }
    let!(:completed_task) { AgentTask.create!(title: 'Completed Task', priority: 'normal', status: 'completed', goal: goal, user: user) }
    let!(:paused_task) { AgentTask.create!(title: 'Paused Task', priority: 'normal', status: 'paused', goal: goal, user: user) }
    
    it 'has active scope' do
      expect(AgentTask.active).to include(active_task)
      expect(AgentTask.active).not_to include(completed_task, paused_task)
    end
    
    it 'has completed scope' do
      expect(AgentTask.completed).to include(completed_task)
      expect(AgentTask.completed).not_to include(active_task, paused_task)
    end
  end
  
  describe 'agentable concern' do
    let(:task) { AgentTask.create!(title: 'Test Task', priority: 'normal', status: 'active', goal: goal, user: user) }
    
    it 'includes agentable functionality' do
      expect(task).to respond_to(:get_llm_history)
      expect(task).to respond_to(:add_to_llm_history)
      expect(task).to respond_to(:agent_active?)
    end
  end
end
