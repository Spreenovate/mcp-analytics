class AbuseAlertJob < ApplicationJob
  queue_as :default

  # Picks up any abuse_events written by the Go ingester that we haven't
  # mailed yet, bundles them into a single digest to the operator, and
  # marks them notified. Runs every 5 minutes via recurring.yml.
  def perform
    events = AbuseEvent.pending_notification.order(:created_at).limit(200).to_a
    return if events.empty?

    OperatorMailer.abuse_alert(events: events).deliver_later
    AbuseEvent.where(id: events.map(&:id)).update_all(notified_at: Time.current)
  end
end
