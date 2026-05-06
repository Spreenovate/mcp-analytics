class CreateOauthAuthorizationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_authorization_requests do |t|
      t.references :oauth_client, null: false, foreign_key: true
      t.string :redirect_uri, null: false
      t.string :state
      t.string :scope, default: "read:analytics", null: false
      t.string :code_challenge, null: false
      t.string :code_challenge_method, null: false # 'S256'
      t.string :request_token, null: false # opaque id used to resume after email click
      t.string :email
      t.references :user, foreign_key: true # populated when user identified
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end

    add_index :oauth_authorization_requests, :request_token, unique: true
    add_index :oauth_authorization_requests, :expires_at
  end
end
