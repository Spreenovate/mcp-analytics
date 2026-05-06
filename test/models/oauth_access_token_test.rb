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

  test "touch_used! updates last_used_at on first call" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    assert_nil t.last_used_at
    travel 5.seconds do
      t.touch_used!
    end
    assert t.reload.last_used_at.present?
  end

  # Block 5: throttle — high-rate clients must not write a row per call.
  test "touch_used! is a no-op when called inside the throttle window" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    t.touch_used!
    first = t.reload.last_used_at

    travel(OauthAccessToken::TOUCH_USED_THROTTLE - 1.second) do
      assert_no_changes -> { t.reload.last_used_at } do
        t.touch_used!
      end
    end
    assert_equal first, t.reload.last_used_at
  end

  test "touch_used! writes again once the throttle window passes" do
    t = OauthAccessToken.create!(user: @user, oauth_client: @client, scope: "analytics:read")
    t.touch_used!
    first = t.reload.last_used_at

    travel(OauthAccessToken::TOUCH_USED_THROTTLE + 1.second) do
      t.touch_used!
    end
    assert_operator t.reload.last_used_at, :>, first
  end
end
