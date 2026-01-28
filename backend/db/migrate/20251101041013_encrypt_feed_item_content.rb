class EncryptFeedItemContent < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Encrypting existing FeedItem content" do
      # Enable support for unencrypted data during migration
      original_config = ActiveRecord::Encryption.config.support_unencrypted_data
      ActiveRecord::Encryption.config.support_unencrypted_data = true

      FeedItem.find_each do |item|
        item.save!(validate: false)
      end

      ActiveRecord::Encryption.config.support_unencrypted_data = original_config
    end
  end

  def down
    # Decryption would require the same keys, so this is a no-op
    # Data remains encrypted but readable with proper keys
  end
end
