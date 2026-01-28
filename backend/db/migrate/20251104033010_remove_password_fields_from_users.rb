class RemovePasswordFieldsFromUsers < ActiveRecord::Migration[8.0]
  def change
    # Make password_digest nullable first (was NOT NULL)
    change_column_null :users, :password_digest, true

    # Remove password-related columns
    remove_column :users, :password_digest, :string
    remove_column :users, :reset_token_digest, :string
    remove_column :users, :reset_sent_at, :datetime
  end
end
