class CreateEmailVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :email_verifications do |t|
      t.string :email, null: false
      t.string :verify_token, null: false
      t.string :pending_user_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :created_at, null: false
    end

    add_index :email_verifications, :verify_token, unique: true
    add_index :email_verifications, :pending_user_id, unique: true
    add_index :email_verifications, :email
    add_index :email_verifications, :expires_at
  end
end
