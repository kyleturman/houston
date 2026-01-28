class DecryptUserEmails < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Decrypting user emails to plaintext for admin visibility" do
      # Temporarily enable encryption on email field to read encrypted values
      User.encrypts :email, deterministic: true

      # Support reading unencrypted data in case migration runs twice
      original_config = ActiveRecord::Encryption.config.support_unencrypted_data
      ActiveRecord::Encryption.config.support_unencrypted_data = true

      # Read each user (which decrypts email) and save (which saves as plaintext)
      User.find_each do |user|
        # Force reload to decrypt, then save without validation
        # The save will write plaintext since User model no longer has encrypts :email
        user.save!(validate: false)
      end

      ActiveRecord::Encryption.config.support_unencrypted_data = original_config
    end
  end

  def down
    # Re-encrypting would require adding encryption back to model
    # This is a one-way migration for admin visibility
    say "Email decryption is intentional for admin monitoring - not reversing"
  end
end
