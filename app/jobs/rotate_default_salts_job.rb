class RotateDefaultSaltsJob < ApplicationJob
  queue_as :default

  # Rotates site_salt for sites in 'default' privacy mode after 365 days.
  # 'strict' mode uses a daily salt generated in-process by the Go ingester.
  # 'all' mode uses a persistent cookie client-side and doesn't need rotation.
  def perform
    cutoff = 365.days.ago
    Site.active.where(privacy_mode: "default")
        .where("salt_rotated_at IS NULL OR salt_rotated_at < ?", cutoff)
        .find_each(&:rotate_salt!)
  end
end
