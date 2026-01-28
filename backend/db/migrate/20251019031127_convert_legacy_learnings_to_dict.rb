class ConvertLegacyLearningsToDict < ActiveRecord::Migration[8.0]
  def up
    # Convert legacy string learnings to dictionary format
    Goal.find_each do |goal|
      next if goal.learnings.blank?
      
      # Check if any learnings are strings (legacy format)
      has_legacy = goal.learnings.any? { |l| l.is_a?(String) }
      next unless has_legacy
      
      converted_learnings = goal.learnings.map do |learning|
        if learning.is_a?(String)
          # Convert string to dictionary
          { 'content' => learning, 'created_at' => goal.created_at.iso8601 }
        else
          # Already in dictionary format, ensure keys are strings
          {
            'content' => learning['content'] || learning[:content] || '',
            'created_at' => learning['created_at'] || learning[:created_at] || goal.created_at.iso8601
          }
        end
      end
      
      goal.update_column(:learnings, converted_learnings)
    end
    
    # Also convert for UserAgent if needed
    UserAgent.find_each do |agent|
      next if agent.learnings.blank?
      
      has_legacy = agent.learnings.any? { |l| l.is_a?(String) }
      next unless has_legacy
      
      converted_learnings = agent.learnings.map do |learning|
        if learning.is_a?(String)
          { 'content' => learning, 'created_at' => agent.created_at.iso8601 }
        else
          {
            'content' => learning['content'] || learning[:content] || '',
            'created_at' => learning['created_at'] || learning[:created_at] || agent.created_at.iso8601
          }
        end
      end
      
      agent.update_column(:learnings, converted_learnings)
    end
  end

  def down
    # Reversing this migration would lose created_at information,
    # so we'll just leave the data in dictionary format
    # (it's backward compatible)
  end
end
