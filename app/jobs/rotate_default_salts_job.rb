class RotateDefaultSaltsJob < ApplicationJob
  queue_as :default

  # Rotates site_salt for sites in 'balanced' privacy mode (formerly 'default')
  # after 365 days. 'strict' mode uses a daily salt generated in-process by the
  # Go ingester. 'all' mode uses a persistent cookie client-side and doesn't
  # need rotation.
  #
  # Job class name kept as RotateDefaultSaltsJob for backwards compat with any
  # already-scheduled instances. Privacy-mode rename handled at write-time in
  # Site#normalize_privacy_mode.
  def perform
    cutoff = 365.days.ago
    Site.active.where(privacy_mode: "balanced")
        .where("salt_rotated_at IS NULL OR salt_rotated_at < ?", cutoff)
        .find_each(&:rotate_salt!)
  end
end
