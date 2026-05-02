class CreateOauthAuthorizationCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_authorization_codes do |t|
      t.string :code, null: false
      t.references :user, null: false, foreign_key: true
      t.references :oauth_client, null: false, foreign_key: true
      t.string :redirect_uri, null: false
      t.string :scope, null: false
      t.string :code_challenge, null: false
      t.string :code_challenge_method, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :oauth_authorization_codes, :code, unique: true
    add_index :oauth_authorization_codes, :expires_at
  end
end
