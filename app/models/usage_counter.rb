class UsageCounter < ApplicationRecord
  validates :site_id, presence: true
  validates :month, presence: true, uniqueness: { scope: :site_id }

  def self.increment!(site_id:, count:, at: Time.current)
    month = at.utc.beginning_of_month.to_date

    counter = find_or_create_by!(site_id: site_id, month: month)
    counter.class.where(id: counter.id).update_all("hit_count = hit_count + #{count.to_i}")
  end
end
