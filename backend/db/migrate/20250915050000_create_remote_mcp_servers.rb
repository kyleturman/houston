class CreateRemoteMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :remote_mcp_servers do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :url, null: false
      t.string :auth_type, default: 'none'
      t.boolean :default_enabled, default: false
      t.text :description
      t.json :metadata

      t.timestamps
    end
  end
end