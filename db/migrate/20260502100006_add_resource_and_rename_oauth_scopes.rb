class AddResourceAndRenameOauthScopes < ActiveRecord::Migration[8.1]
  # MCP spec 2025-06-18 + RFC 8707 require audience binding via the
  # `resource` parameter on /authorize and /token. Persist what the client
  # asked for so we can re-validate at every step of the flow.
  #
  # At the same time, rename the single `read:analytics` scope to a pair
  # that matches what tokens actually grant: `analytics:read` (read-only
  # analytics) and `analytics:manage` (add/remove sites). The old name was
  # misleading because the same token allowed `add_site` / `remove_site`.
  def up
    add_column :oauth_authorization_requests, :resource, :string
    add_column :oauth_authorization_codes,    :resource, :string
    add_column :oauth_access_tokens,          :resource, :string

    new_default = "analytics:read analytics:manage"
    change_column_default :oauth_clients, :scope, from: "read:analytics", to: new_default
    change_column_default :oauth_authorization_requests, :scope, from: "read:analytics", to: new_default

    say_with_time "Backfilling existing scopes" do
      execute <<~SQL.squish
        UPDATE oauth_clients
        SET scope = '#{new_default}'
        WHERE scope = 'read:analytics'
      SQL
      execute <<~SQL.squish
        UPDATE oauth_authorization_requests
        SET scope = '#{new_default}'
        WHERE scope = 'read:analytics'
      SQL
      execute <<~SQL.squish
        UPDATE oauth_authorization_codes
        SET scope = '#{new_default}'
        WHERE scope = 'read:analytics'
      SQL
      execute <<~SQL.squish
        UPDATE oauth_access_tokens
        SET scope = '#{new_default}'
        WHERE scope = 'read:analytics'
      SQL
    end
  end

  def down
    old_default = "read:analytics"
    change_column_default :oauth_clients, :scope, from: "analytics:read analytics:manage", to: old_default
    change_column_default :oauth_authorization_requests, :scope, from: "analytics:read analytics:manage", to: old_default

    execute "UPDATE oauth_clients SET scope = '#{old_default}' WHERE scope = 'analytics:read analytics:manage'"
    execute "UPDATE oauth_authorization_requests SET scope = '#{old_default}' WHERE scope = 'analytics:read analytics:manage'"
    execute "UPDATE oauth_authorization_codes SET scope = '#{old_default}' WHERE scope = 'analytics:read analytics:manage'"
    execute "UPDATE oauth_access_tokens SET scope = '#{old_default}' WHERE scope = 'analytics:read analytics:manage'"

    remove_column :oauth_authorization_requests, :resource
    remove_column :oauth_authorization_codes,    :resource
    remove_column :oauth_access_tokens,          :resource
  end
end
