class CreateOauthClients < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients do |t|
      t.string :client_id, null: false
      t.string :client_name, null: false
      t.string :client_uri
      t.string :logo_uri
      t.text :redirect_uris, null: false # JSON-encoded array
      t.string :token_endpoint_auth_method, default: "none", null: false
      t.string :grant_types, default: "authorization_code", null: false
      t.string :response_types, default: "code", null: false
      t.string :scope, default: "read:analytics", null: false
      t.boolean :dynamically_registered, default: false, null: false
      t.timestamps
    end

    add_index :oauth_clients, :client_id, unique: true
  end
end
