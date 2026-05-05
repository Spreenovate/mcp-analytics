require "test_helper"

class OauthClientTest < ActiveSupport::TestCase
  test "auto-generates client_id with mcpa_client_ prefix" do
    c = OauthClient.create!(client_name: "Claude", redirect_uri_list: ["https://claude.ai/callback"])
    assert_match(/\Amcpa_client_/, c.client_id)
  end

  test "rejects empty redirect_uris" do
    c = OauthClient.new(client_name: "X")
    c.redirect_uri_list = []
    assert_not c.valid?
    assert_includes c.errors.full_messages.join, "Redirect uris"
  end

  test "rejects http redirect_uri unless localhost" do
    c = OauthClient.new(client_name: "X")
    c.redirect_uri_list = ["http://evil.example.com/cb"]
    assert_not c.valid?
  end

  test "accepts http://localhost" do
    c = OauthClient.new(client_name: "X")
    c.redirect_uri_list = ["http://localhost:3000/cb"]
    assert c.valid?, c.errors.full_messages.join("; ")
  end

  test "accepts https redirect_uri" do
    c = OauthClient.new(client_name: "X")
    c.redirect_uri_list = ["https://claude.ai/api/oauth/callback"]
    assert c.valid?
  end

  test "accepts native scheme cursor://" do
    c = OauthClient.new(client_name: "Cursor")
    c.redirect_uri_list = ["cursor://oauth/callback"]
    assert c.valid?, c.errors.full_messages.join("; ")
  end

  test "rejects redirect_uri with fragment" do
    c = OauthClient.new(client_name: "X")
    c.redirect_uri_list = ["https://example.com/cb#frag"]
    assert_not c.valid?
  end

  test "allows_redirect_uri? exact-match check" do
    c = OauthClient.create!(client_name: "X", redirect_uri_list: ["https://a.example/cb", "https://b.example/cb"])
    assert c.allows_redirect_uri?("https://a.example/cb")
    assert c.allows_redirect_uri?("https://b.example/cb")
    assert_not c.allows_redirect_uri?("https://a.example/cb?x=1")
    assert_not c.allows_redirect_uri?("https://evil.example/cb")
    assert_not c.allows_redirect_uri?("")
  end

  test "rejects unsupported token_endpoint_auth_method" do
    c = OauthClient.new(client_name: "X", token_endpoint_auth_method: "client_secret_basic")
    c.redirect_uri_list = ["https://x.example/cb"]
    assert_not c.valid?
  end

  # --- DCR abuse caps -----------------------------------------------------

  test "rejects more than MAX_REDIRECT_URIS redirect URIs" do
    c = OauthClient.new(client_name: "Spammy")
    c.redirect_uri_list = (1..6).map { |i| "https://app#{i}.example/cb" }
    assert_not c.valid?
    assert_match(/at most/, c.errors[:redirect_uris].join)
  end

  test "rejects redirect URI longer than MAX_REDIRECT_URI_LENGTH" do
    c = OauthClient.new(client_name: "Long")
    c.redirect_uri_list = [ "https://example.com/" + ("a" * 600) ]
    assert_not c.valid?
  end

  test "rejects logo_uri longer than 500 chars" do
    c = OauthClient.new(client_name: "X", logo_uri: "https://x.example/" + ("a" * 600))
    c.redirect_uri_list = [ "https://x.example/cb" ]
    assert_not c.valid?
  end

  test "rejects client_uri longer than 500 chars" do
    c = OauthClient.new(client_name: "X", client_uri: "https://x.example/" + ("a" * 600))
    c.redirect_uri_list = [ "https://x.example/cb" ]
    assert_not c.valid?
  end
end
