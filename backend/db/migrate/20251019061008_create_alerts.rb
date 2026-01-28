class CreateAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :goal, foreign_key: true  # optional - can be from UserAgent
      t.string :title, null: false
      t.text :content, null: false
      t.integer :priority, null: false, default: 0  # 0=medium, 1=high, 2=urgent
      t.string :action_url
      t.datetime :expires_at, null: false
      t.integer :status, default: 0  # active, dismissed, acted_on, expired

      t.timestamps
    end

    add_index :alerts, [:user_id, :status]
    add_index :alerts, :priority
    add_index :alerts, :expires_at
  end
end
