class UnknownSiteHit < ApplicationRecord
  validates :site_id_attempted, presence: true
  validates :hour, presence: true, uniqueness: { scope: :site_id_attempted }

  # Atomic UPSERT. Mirrors the Go ingester's INSERT ... ON CONFLICT.
  def self.bump!(site_id_attempted:, at: Time.current, count: 1)
    hour = at.utc.beginning_of_hour
    now  = Time.current
    n    = count.to_i
    return if n.zero?

    connection.exec_insert(<<~SQL, "UnknownSiteHit Upsert", [ site_id_attempted, hour, n, now, now ])
      INSERT INTO unknown_site_hits (site_id_attempted, hour, hit_count, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(site_id_attempted, hour) DO UPDATE
        SET hit_count = hit_count + excluded.hit_count,
            updated_at = excluded.updated_at
    SQL
  end
end
