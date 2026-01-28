# frozen_string_literal: true

# Ensure Active Record Encryption keys are sourced from environment variables in all environments.
# This avoids relying on Rails credentials for local/dev Docker setups where .env is the source of truth.
Rails.application.configure do
  primary   = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
  deter     = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
  salt      = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']

  if primary.present? && deter.present? && salt.present?
    config.active_record.encryption.primary_key = primary
    config.active_record.encryption.deterministic_key = deter
    config.active_record.encryption.key_derivation_salt = salt
  else
    Rails.logger.warn(
      "ActiveRecord Encryption keys are missing. " \
      "Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, " \
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY, and " \
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT in your environment."
    )
  end
end
