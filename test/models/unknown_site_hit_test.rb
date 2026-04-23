require "test_helper"

class UnknownSiteHitTest < ActiveSupport::TestCase
  test "bump! creates row on first call" do
    UnknownSiteHit.bump!(site_id_attempted: "ghost1", count: 3)
    hour = Time.current.utc.beginning_of_hour
    row = UnknownSiteHit.find_by(site_id_attempted: "ghost1", hour: hour)
    assert_equal 3, row.hit_count
  end

  test "bump! adds to existing row (UPSERT)" do
    UnknownSiteHit.bump!(site_id_attempted: "ghost2", count: 2)
    UnknownSiteHit.bump!(site_id_attempted: "ghost2", count: 4)
    hour = Time.current.utc.beginning_of_hour
    row = UnknownSiteHit.find_by(site_id_attempted: "ghost2", hour: hour)
    assert_equal 6, row.hit_count
  end

  test "bump! is a no-op when count is zero" do
    UnknownSiteHit.bump!(site_id_attempted: "ghostzero", count: 0)
    assert_nil UnknownSiteHit.find_by(site_id_attempted: "ghostzero")
  end

  test "bump! buckets by hour" do
    UnknownSiteHit.bump!(site_id_attempted: "g3", at: Time.utc(2026, 4, 23, 10, 30), count: 2)
    UnknownSiteHit.bump!(site_id_attempted: "g3", at: Time.utc(2026, 4, 23, 11,  5), count: 5)

    rows = UnknownSiteHit.where(site_id_attempted: "g3").order(:hour)
    assert_equal 2, rows.count
    assert_equal [2, 5], rows.map(&:hit_count)
  end
end
