class CreateOauthAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_access_tokens do |t|
      t.string :token, null: false
      t.references :user, null: false, foreign_key: true
      t.references :oauth_client, null: false, foreign_key: true
      t.string :scope, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :expires_at
    add_index :oauth_access_tokens, :revoked_at
  end
end
