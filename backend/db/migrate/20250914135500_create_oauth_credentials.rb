# frozen_string_literal: true

class CreateOauthCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :server_name, null: false
      t.string :provider, null: true
      t.text :access_token, null: true
      t.text :refresh_token, null: true
      t.datetime :expires_at, null: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :oauth_credentials, [:user_id, :server_name], unique: true
  end
end
