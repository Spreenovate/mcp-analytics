require "test_helper"

class PruneOauthAuditEventsJobTest < ActiveJob::TestCase
  setup do
    @user   = User.create!(email: "prune@example.com", email_verified_at: Time.current)
    @client = OauthClient.create!(client_name: "X",
                                   redirect_uri_list: [ "https://x.example/cb" ])
  end

  test "deletes events older than RETENTION_PERIOD, keeps newer ones" do
    cutoff = PruneOauthAuditEventsJob::RETENTION_PERIOD

    old_event   = OauthAuditEvent.create!(event: "consent_granted", user: @user)
    old_event.update_column(:created_at, (cutoff + 1.day).ago)

    fresh_event = OauthAuditEvent.create!(event: "consent_granted", user: @user)
    fresh_event.update_column(:created_at, (cutoff - 1.day).ago)

    assert_difference -> { OauthAuditEvent.count }, -1 do
      PruneOauthAuditEventsJob.new.perform
    end

    assert_not OauthAuditEvent.exists?(old_event.id),  "row past retention should be gone"
    assert     OauthAuditEvent.exists?(fresh_event.id), "row inside retention must stay"
  end

  test "delete_all bypasses the model's append-only callbacks (no ReadOnlyRecord)" do
    old_event = OauthAuditEvent.create!(event: "token_issued", user: @user)
    old_event.update_column(:created_at, (PruneOauthAuditEventsJob::RETENTION_PERIOD + 1.day).ago)

    # Sanity: direct .destroy raises (append-only enforcement still in place).
    assert_raises(ActiveRecord::ReadOnlyRecord) { old_event.destroy }

    # But the retention job uses delete_all which skips callbacks.
    assert_nothing_raised { PruneOauthAuditEventsJob.new.perform }
    assert_not OauthAuditEvent.exists?(old_event.id)
  end

  test "no-op when no events are past retention" do
    OauthAuditEvent.create!(event: "token_issued", user: @user) # fresh, default created_at

    assert_no_difference -> { OauthAuditEvent.count } do
      PruneOauthAuditEventsJob.new.perform
    end
  end
end
