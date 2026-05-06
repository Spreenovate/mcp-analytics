require "test_helper"

class OauthAuthorizationRequestTest < ActiveSupport::TestCase
  setup do
    @client = OauthClient.create!(client_name: "X", redirect_uri_list: ["https://x.example/cb"])
  end

  def build_request(**overrides)
    defaults = {
      oauth_client: @client,
      redirect_uri: "https://x.example/cb",
      code_challenge: "challenge",
      code_challenge_method: "S256",
      scope: "analytics:read"
    }
    OauthAuthorizationRequest.create!(defaults.merge(overrides))
  end

  test "auto-generates request_token + 30 min expiry" do
    r = build_request
    assert r.request_token.length > 20
    assert r.usable?
    assert_in_delta 30.minutes.from_now.to_i, r.expires_at.to_i, 5
  end

  test "rejects unsupported code_challenge_method" do
    r = OauthAuthorizationRequest.new(
      oauth_client: @client, redirect_uri: "https://x.example/cb",
      code_challenge: "x", code_challenge_method: "plain", scope: "analytics:read"
    )
    assert_not r.valid?
  end

  test "mark_consumed! sets consumed_at and flips usable?" do
    r = build_request
    r.mark_consumed!
    assert_not r.usable?
    assert r.consumed?
  end
end
