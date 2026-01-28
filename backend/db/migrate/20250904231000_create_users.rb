class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :reset_token_digest
      t.datetime :reset_sent_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_sent_at
  end
end
