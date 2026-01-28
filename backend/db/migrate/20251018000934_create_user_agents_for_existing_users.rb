class CreateUserAgentsForExistingUsers < ActiveRecord::Migration[8.0]
  def up
    # Create UserAgent for any existing users that don't have one
    User.find_each do |user|
      next if user.user_agent.present?
      
      UserAgent.create!(user: user)
      Rails.logger.info("[Migration] Created UserAgent for user_id=#{user.id}")
    rescue => e
      Rails.logger.error("[Migration] Failed to create UserAgent for user_id=#{user.id}: #{e.message}")
    end
  end

  def down
    # No need to remove UserAgents on rollback - they're valid data
  end
end
