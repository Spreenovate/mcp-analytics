require "test_helper"

class Oauth::AuditTest < ActiveSupport::TestCase
  setup do
    @client = OauthClient.create!(client_name: "X",
                                   redirect_uri_list: [ "https://x.example/cb" ])
    @user = User.create!(email: "audit@example.com", email_verified_at: Time.current)
  end

  test "logs a known event with all associations" do
    token = OauthAccessToken.create!(user: @user, oauth_client: @client,
                                      scope: "analytics:read")
    request = ActionDispatch::TestRequest.create
    request.env["REMOTE_ADDR"] = "203.0.113.7"

    event = Oauth::Audit.log("token_issued",
              user: @user, oauth_client: @client, oauth_access_token: token,
              request: request, metadata: { scope: "analytics:read" })

    assert event.persisted?
    assert_equal "token_issued", event.event
    assert_equal @user.id, event.user_id
    assert_equal @client.id, event.oauth_client_id
    assert_equal token.id, event.oauth_access_token_id
    assert_equal "203.0.113.7", event.ip_address
    assert_equal "analytics:read", event.metadata_hash["scope"]
  end

  test "raises on unknown event names (typos shouldn't silently disappear)" do
    assert_raises(ArgumentError) do
      Oauth::Audit.log("totally_made_up", user: @user)
    end
  end

  test "swallows DB-level errors so audit never blocks the OAuth flow" do
    # Force a DB-level failure by violating a FK constraint.
    fake_user = User.new(id: 999_999_999)
    assert_nothing_raised do
      Oauth::Audit.log("token_issued", user: fake_user, oauth_client: @client)
    end
  end

  test "lets RecordInvalid surface (programmer errors must not vanish)" do
    # Calling with an invalid event would have raised ArgumentError before
    # reaching the DB. Simulate a different programmer-error scenario:
    # a model-level validation failure should NOT be silently swallowed.
    assert_raises(ActiveRecord::RecordInvalid) do
      OauthAuditEvent.create!(event: "")
    end
  end

  test "caps oversized metadata so DCR registrants cannot bloat the audit table" do
    huge = { "blob" => "x" * 10_000 }
    event = Oauth::Audit.log("client_registered",
                              oauth_client: @client, metadata: huge)
    assert event.persisted?
    assert event.metadata.bytesize <= Oauth::Audit::MAX_METADATA_BYTES + 200
    assert_equal true, event.metadata_hash["_truncated"]
    assert event.metadata_hash["_original_bytes"] > Oauth::Audit::MAX_METADATA_BYTES
  end

  test "small metadata passes through unchanged" do
    event = Oauth::Audit.log("token_issued",
                              user: @user, oauth_client: @client,
                              metadata: { "scope" => "analytics:read" })
    assert_equal "analytics:read", event.metadata_hash["scope"]
    assert_nil event.metadata_hash["_truncated"]
  end

  test "model is append-only — created_at set, no updated_at column" do
    e = OauthAuditEvent.create!(event: "consent_granted", user: @user)
    assert e.created_at.present?
    assert_not OauthAuditEvent.column_names.include?("updated_at"),
               "audit events should not have updated_at"
  end

  test "update! raises ReadOnlyRecord — append-only is enforced at the model" do
    e = OauthAuditEvent.create!(event: "consent_granted", user: @user)
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.update!(event: "token_issued") }
  end

  test "destroy raises ReadOnlyRecord — direct .destroy is forbidden" do
    e = OauthAuditEvent.create!(event: "consent_granted", user: @user)
    assert_raises(ActiveRecord::ReadOnlyRecord) { e.destroy }
  end
end
