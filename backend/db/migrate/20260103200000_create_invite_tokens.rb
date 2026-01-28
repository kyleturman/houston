# frozen_string_literal: true

class CreateInviteTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :invite_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at  # nil = never expires
      t.datetime :first_used_at  # set on first claim, starts 24h reuse window
      t.datetime :revoked_at  # manual revocation

      t.timestamps
    end

    add_index :invite_tokens, :first_used_at
    add_index :invite_tokens, :expires_at
  end
end
