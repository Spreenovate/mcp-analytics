require "test_helper"

class OauthAccessTokenTest < ActiveSupport::TestCase
  setup do
    @client = OauthClient.create!(client_name: "X", redirect_uri_list: ["https://x.example/cb"])
    @user   = User.create!(email: "tk@example.com", email_verified_at: Time.current)
  end

  test "auto-generates access token (mcpa_oauth_ prefix, 24h expiry) and refresh token (mcpa_refresh_, 90d)" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    assert_match(/\Amcpa_oauth_/,   t.token)
    assert_match(/\Amcpa_refresh_/, t.refresh_token)
    assert_in_delta 24.hours.from_now.to_i, t.expires_at.to_i, 5
    assert_in_delta 90.days.from_now.to_i,  t.refresh_token_expires_at.to_i, 5
    assert t.active?
    assert t.refresh_active?
  end

  test "active? false after revoke or expiry" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    t.revoke!
    assert_not t.active?

    t2 = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read", expires_at: 1.minute.ago)
    assert_not t2.active?
  end

  test "touch_used! updates last_used_at without bumping updated_at" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    assert_nil t.last_used_at
    travel 5.seconds do
      t.touch_used!
    end
    assert t.reload.last_used_at.present?
  end
end
