require "test_helper"

class UsageCounterTest < ActiveSupport::TestCase
  test "increment! creates row on first call" do
    UsageCounter.increment!(site_id: "abc12345", count: 7)
    row = UsageCounter.find_by(site_id: "abc12345", month: Date.current.beginning_of_month)
    assert_equal 7, row.hit_count
  end

  test "increment! adds to existing row (UPSERT)" do
    UsageCounter.increment!(site_id: "abc12345", count: 5)
    UsageCounter.increment!(site_id: "abc12345", count: 3)
    row = UsageCounter.find_by(site_id: "abc12345", month: Date.current.beginning_of_month)
    assert_equal 8, row.hit_count
  end

  test "increment! buckets per (site_id, month)" do
    UsageCounter.increment!(site_id: "site1", count: 4)
    UsageCounter.increment!(site_id: "site2", count: 9)
    UsageCounter.increment!(site_id: "site1", count: 1, at: 1.month.ago)

    current_month = Date.current.beginning_of_month
    last_month    = 1.month.ago.utc.beginning_of_month.to_date

    assert_equal 4, UsageCounter.find_by(site_id: "site1", month: current_month).hit_count
    assert_equal 9, UsageCounter.find_by(site_id: "site2", month: current_month).hit_count
    assert_equal 1, UsageCounter.find_by(site_id: "site1", month: last_month).hit_count
  end

  test "increment! with zero count is a no-op" do
    UsageCounter.increment!(site_id: "noop", count: 0)
    assert_nil UsageCounter.find_by(site_id: "noop")
  end

  test "increment! survives concurrent inserts (no duplicate row)" do
    threads = 4.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          5.times { UsageCounter.increment!(site_id: "concurrent", count: 1) }
        end
      end
    end
    threads.each(&:join)

    rows = UsageCounter.where(site_id: "concurrent")
    assert_equal 1, rows.count, "should have exactly one row, not race-duplicated"
    assert_equal 20, rows.first.hit_count
  end
end
