class CreateOauthAuditEvents < ActiveRecord::Migration[8.1]
  # Append-only audit trail for OAuth-relevant events. Anthropic / ChatGPT
  # connector reviewers regularly ask "how do you prove a user authorised
  # this client?" — this table is the answer. Indexed by user and client
  # so a Settings page can render "what did this connector do, when?"
  def change
    create_table :oauth_audit_events do |t|
      t.string :event, null: false  # see Oauth::Audit::EVENTS
      t.references :user, foreign_key: true            # null when client-only event
      t.references :oauth_client, foreign_key: true    # null when user-only event
      t.references :oauth_access_token, foreign_key: true
      t.string :ip_address, limit: 45                   # IPv6-safe
      t.text :metadata                                  # JSON-encoded
      t.datetime :created_at, null: false
    end

    add_index :oauth_audit_events, :event
    add_index :oauth_audit_events, :created_at
  end
end
