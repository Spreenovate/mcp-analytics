class UsageCounter < ApplicationRecord
  validates :site_id, presence: true
  validates :month, presence: true, uniqueness: { scope: :site_id }

  # Atomic UPSERT. Mirrors the Go ingester's INSERT ... ON CONFLICT semantics
  # so Rails and Go writers stay consistent.
  def self.increment!(site_id:, count:, at: Time.current)
    month = at.utc.beginning_of_month.to_date
    now   = Time.current
    n     = count.to_i
    return if n.zero?

    connection.exec_insert(<<~SQL, "UsageCounter Upsert", [site_id, month, n, now, now])
      INSERT INTO usage_counters (site_id, month, hit_count, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(site_id, month) DO UPDATE
        SET hit_count = hit_count + excluded.hit_count,
            updated_at = excluded.updated_at
    SQL
  end
end
