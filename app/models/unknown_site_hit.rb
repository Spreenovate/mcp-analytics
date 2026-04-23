class UnknownSiteHit < ApplicationRecord
  validates :site_id_attempted, presence: true
  validates :hour, presence: true, uniqueness: { scope: :site_id_attempted }

  def self.bump!(site_id_attempted:, at: Time.current, count: 1)
    hour = at.utc.beginning_of_hour

    record = find_or_create_by!(site_id_attempted: site_id_attempted, hour: hour)
    record.class.where(id: record.id).update_all("hit_count = hit_count + #{count.to_i}")
  end
end
