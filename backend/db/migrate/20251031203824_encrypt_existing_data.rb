# frozen_string_literal: true

class EncryptExistingData < ActiveRecord::Migration[8.0]
  def up
    # Re-save all records to encrypt existing plaintext data
    # Enable support for reading unencrypted data during migration
    original_config = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    Rails.logger.info("[Migration] Encrypting existing Goal records...")
    Goal.find_each do |goal|
      goal.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing AgentTask records...")
    AgentTask.find_each do |task|
      task.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing UserAgent records...")
    UserAgent.find_each do |agent|
      agent.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing AgentHistory records...")
    AgentHistory.find_each do |history|
      history.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing UserMcpConnection records...")
    UserMcpConnection.find_each do |connection|
      connection.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing ThreadMessage records...")
    ThreadMessage.find_each do |message|
      message.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing Alert records...")
    Alert.find_each do |alert|
      alert.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encrypting existing User records...")
    User.find_each do |user|
      user.save!(validate: false)
    end

    Rails.logger.info("[Migration] Encryption complete!")
  rescue => e
    Rails.logger.error("[Migration] Encryption failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  ensure
    # Restore original config
    ActiveRecord::Encryption.config.support_unencrypted_data = original_config
  end

  def down
    Rails.logger.warn("[Migration] Cannot decrypt data - rollback not supported for encryption migration")
    Rails.logger.warn("[Migration] Restore from backup if you need to rollback")
  end
end
