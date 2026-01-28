class BackfillThreadMessageSessions < ActiveRecord::Migration[8.0]
  def up
    say "Backfilling thread messages with agent_history_id..."

    ['Goal', 'AgentTask', 'UserAgent'].each do |agentable_type|
      say "Processing #{agentable_type} records..."

      agentable_type.constantize.find_each do |agentable|
        histories = AgentHistory
          .where(agentable_type: agentable_type, agentable_id: agentable.id)
          .order(:completed_at)

        next if histories.empty?

        histories.each do |history|
          updated_count = ThreadMessage
            .where(
              agentable_type: agentable_type,
              agentable_id: agentable.id,
              agent_history_id: nil
            )
            .where('created_at >= ? AND created_at <= ?',
                   history.started_at,
                   history.completed_at)
            .update_all(agent_history_id: history.id)

          say "  Associated #{updated_count} messages with AgentHistory##{history.id}" if updated_count > 0
        end
      end
    end

    say "Backfill complete!"
  end

  def down
    say "Clearing agent_history_id from thread messages..."
    ThreadMessage.update_all(agent_history_id: nil)
    say "Cleared agent_history_id from all thread messages"
  end
end
