class AddRefreshTokensToOauthAccessTokens < ActiveRecord::Migration[8.1]
  # Block 4: introduce refresh tokens with rotation per OAuth 2.1 §4.3.1.
  #
  # Existing tokens (issued under Block 1-3 with VALID_FOR = 365.days and
  # no refresh) keep working until their access_token expires. New tokens
  # ship with a 24h access + 90d refresh window and rotate the refresh
  # value on every redemption.
  def change
    add_column :oauth_access_tokens, :refresh_token,            :string
    add_column :oauth_access_tokens, :refresh_token_expires_at, :datetime
    add_column :oauth_access_tokens, :refresh_token_used_at,    :datetime

    add_index  :oauth_access_tokens, :refresh_token, unique: true
    add_index  :oauth_access_tokens, :refresh_token_expires_at
  end
end
