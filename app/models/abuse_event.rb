class AbuseEvent < ApplicationRecord
  validates :ip, presence: true
  validates :kind, presence: true
  validates :unique_sites, numericality: { greater_than_or_equal_to: 0 }
  validates :blocked_until, presence: true

  scope :pending_notification, -> { where(notified_at: nil) }

  def mark_notified!
    update!(notified_at: Time.current)
  end
end
