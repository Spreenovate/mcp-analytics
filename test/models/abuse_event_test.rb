require "test_helper"

class AbuseEventTest < ActiveSupport::TestCase
  test "pending_notification excludes already-notified rows" do
    fresh = AbuseEvent.create!(ip: "1.1.1.1", unique_sites: 120,
                               blocked_until: 1.hour.from_now)
    done  = AbuseEvent.create!(ip: "2.2.2.2", unique_sites: 150,
                               blocked_until: 1.hour.from_now,
                               notified_at: Time.current)

    assert_includes AbuseEvent.pending_notification, fresh
    assert_not_includes AbuseEvent.pending_notification, done
  end

  test "mark_notified! sets timestamp" do
    e = AbuseEvent.create!(ip: "3.3.3.3", unique_sites: 101,
                           blocked_until: 1.hour.from_now)
    assert_nil e.notified_at
    e.mark_notified!
    assert e.notified_at.present?
  end

  test "requires ip, unique_sites >= 0, blocked_until" do
    e = AbuseEvent.new(unique_sites: -1)
    assert_not e.valid?
    assert_includes e.errors[:ip], "can't be blank"
    assert_includes e.errors[:unique_sites], "must be greater than or equal to 0"
    assert_includes e.errors[:blocked_until], "can't be blank"
  end
end
