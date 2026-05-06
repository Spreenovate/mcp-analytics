class BackfillAndRequireOauthTokenResource < ActiveRecord::Migration[8.0]
  # Pre-Block-3 OAuth access tokens have resource=nil. The controller used
  # to grandfather them as "valid for THIS resource server only" — but RFC
  # 8707 audience-binding becomes ineffective if any code path can mint a
  # nil-resource row in the future. Backfill once, then enforce presence
  # so future rows can't bypass the audience check.
  def up
    canonical = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com") + "/mcp"
    OauthAccessToken.where(resource: nil).update_all(resource: canonical)

    # Defense in depth: also backfill authorization codes and requests, so
    # the chain from /authorize → /token → access_token can't reintroduce
    # nil resources via legacy rows.
    OauthAuthorizationRequest.where(resource: nil).update_all(resource: canonical) if defined?(OauthAuthorizationRequest)
    OauthAuthorizationCode.where(resource: nil).update_all(resource: canonical)    if defined?(OauthAuthorizationCode)

    change_column_null :oauth_access_tokens, :resource, false
  end

  def down
    change_column_null :oauth_access_tokens, :resource, true
  end
end
