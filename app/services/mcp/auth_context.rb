module Mcp
  # Carries the result of authenticating an MCP request: the user (if any),
  # how they authenticated (oauth, legacy api_token, or anonymous), and the
  # OAuth scopes granted to this token.
  #
  # Tools dispatch needs to distinguish OAuth from legacy auth so we can
  # withhold capabilities (like regenerating the master api_token) from
  # OAuth-issued tokens, where the OAuth client could otherwise use the
  # call to extract a long-lived credential that bypasses the OAuth grant's
  # revocation lifecycle.
  class AuthContext
    attr_reader :user, :auth_method, :scope_string, :oauth_token

    def self.anonymous
      new(user: nil, auth_method: :anonymous, scope_string: "", oauth_token: nil)
    end

    def self.legacy(user)
      # Legacy api_token isn't scoped; it grants everything the user has.
      new(user: user, auth_method: :legacy, scope_string: Oauth::Scopes::DEFAULT, oauth_token: nil)
    end

    def self.oauth(oauth_token)
      new(user: oauth_token.user,
          auth_method: :oauth,
          scope_string: oauth_token.scope,
          oauth_token: oauth_token)
    end

    def initialize(user:, auth_method:, scope_string:, oauth_token:)
      @user = user
      @auth_method = auth_method
      @scope_string = scope_string.to_s
      @oauth_token = oauth_token
    end

    def authenticated?
      !user.nil?
    end

    def oauth?
      auth_method == :oauth
    end

    def granted?(*required_scopes)
      Oauth::Scopes.granted?(scope_string, required_scopes)
    end
  end
end
