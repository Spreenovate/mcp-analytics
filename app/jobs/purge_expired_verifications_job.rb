class PurgeExpiredVerificationsJob < ApplicationJob
  queue_as :default

  # Keep the table small and remove anything that's either used or well past its
  # expiry window.
  def perform
    EmailVerification
      .where("used_at IS NOT NULL OR expires_at < ?", 7.days.ago)
      .delete_all

    MagicLink
      .where("used_at IS NOT NULL OR expires_at < ?", 1.day.ago)
      .delete_all

    UnknownSiteHit
      .where("hour < ?", 30.days.ago)
      .delete_all
  end
end
