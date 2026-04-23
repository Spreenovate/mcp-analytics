require "test_helper"

class AbuseAlertJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test "mails pending events and marks them notified" do
    e1 = AbuseEvent.create!(ip: "1.1.1.1", unique_sites: 120, blocked_until: 1.hour.from_now)
    e2 = AbuseEvent.create!(ip: "2.2.2.2", unique_sites: 150, blocked_until: 1.hour.from_now)

    assert_enqueued_emails 1 do
      AbuseAlertJob.perform_now
    end

    assert e1.reload.notified_at.present?
    assert e2.reload.notified_at.present?
  end

  test "no mail when nothing is pending" do
    AbuseEvent.create!(ip: "3.3.3.3", unique_sites: 101,
                       blocked_until: 1.hour.from_now,
                       notified_at: Time.current)

    assert_enqueued_emails 0 do
      AbuseAlertJob.perform_now
    end
  end

  test "does not re-notify previously notified events" do
    already = AbuseEvent.create!(ip: "4.4.4.4", unique_sites: 200,
                                 blocked_until: 1.hour.from_now,
                                 notified_at: 10.minutes.ago)
    original = already.notified_at

    assert_enqueued_emails 0 do
      AbuseAlertJob.perform_now
    end
    assert_equal original.to_i, already.reload.notified_at.to_i
  end
end

class OperatorMailerAbuseAlertTest < ActionMailer::TestCase
  test "abuse_alert bundles events into one message" do
    events = [
      AbuseEvent.create!(ip: "5.5.5.5", unique_sites: 101, blocked_until: 1.hour.from_now),
      AbuseEvent.create!(ip: "6.6.6.6", unique_sites: 250, blocked_until: 1.hour.from_now)
    ]
    mail = OperatorMailer.abuse_alert(events: events)
    assert_match "2 IP(s) blocked", mail.subject
    assert_match "5.5.5.5", mail.body.to_s
    assert_match "6.6.6.6", mail.body.to_s
    assert_match "250 distinct", mail.body.to_s
  end
end
