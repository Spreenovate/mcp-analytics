require "test_helper"

class OauthAuthorizationCodeTest < ActiveSupport::TestCase
  setup do
    @client = OauthClient.create!(client_name: "X", redirect_uri_list: ["https://x.example/cb"])
    @user   = User.create!(email: "ac@example.com", email_verified_at: Time.current)
  end

  test "auto-generates code + 10 minute expiry" do
    c = OauthAuthorizationCode.create!(
      user: @user, oauth_client: @client,
      redirect_uri: "https://x.example/cb",
      scope: "read:analytics",
      code_challenge: "abc", code_challenge_method: "S256"
    )
    assert c.code.length > 20
    assert_in_delta 10.minutes.from_now.to_i, c.expires_at.to_i, 5
  end

  test "verify_pkce! returns true for matching S256 verifier/challenge pair" do
    verifier  = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    c = OauthAuthorizationCode.create!(
      user: @user, oauth_client: @client,
      redirect_uri: "https://x.example/cb",
      scope: "read:analytics",
      code_challenge: challenge, code_challenge_method: "S256"
    )
    assert c.verify_pkce!(verifier)
    assert_not c.verify_pkce!(verifier + "x")
    assert_not c.verify_pkce!("")
  end

  test "usable? false after used_at set or after expiry" do
    c = OauthAuthorizationCode.create!(
      user: @user, oauth_client: @client,
      redirect_uri: "https://x.example/cb",
      scope: "read:analytics",
      code_challenge: "abc", code_challenge_method: "S256"
    )
    assert c.usable?

    c.update!(expires_at: 1.minute.ago)
    assert_not c.usable?

    c.update!(expires_at: 5.minutes.from_now)
    c.mark_used!
    assert_not c.usable?
  end
end
