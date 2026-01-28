class CreatePlaidConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :plaid_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.text :access_token, null: false
      t.string :item_id, null: false
      t.string :institution_id
      t.string :institution_name
      t.string :status, null: false, default: 'active'
      t.jsonb :metadata, default: {}
      t.string :cursor
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :plaid_connections, :item_id, unique: true
    add_index :plaid_connections, [:user_id, :status]
  end
end
