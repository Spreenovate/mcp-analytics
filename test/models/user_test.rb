require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "auto-generates api_token on create" do
    user = User.create!(email: "a@example.com")
    assert_match(/\Amcpa_/, user.api_token)
  end

  test "requires unique email" do
    User.create!(email: "dup@example.com")
    dup = User.new(email: "dup@example.com")
    assert_not dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "requires valid email format" do
    user = User.new(email: "not-an-email")
    assert_not user.valid?
  end

  test "plan defaults to free and plan_limit is 100_000" do
    user = User.create!(email: "b@example.com")
    assert_equal "free", user.plan
    assert_equal 100_000, user.plan_limit
  end

  test "active_sites excludes soft-deleted" do
    user = User.create!(email: "c@example.com")
    keep = user.sites.create!(domain: "keep.com", privacy_mode: "strict")
    gone = user.sites.create!(domain: "gone.com", privacy_mode: "strict")
    gone.soft_delete!

    assert_includes user.active_sites, keep
    assert_not_includes user.active_sites, gone
  end

  test "hits_this_month sums UsageCounter for active sites only" do
    user = User.create!(email: "d@example.com")
    s1   = user.sites.create!(domain: "s1.com", privacy_mode: "strict")
    s2   = user.sites.create!(domain: "s2.com", privacy_mode: "strict")
    gone = user.sites.create!(domain: "g.com",  privacy_mode: "strict")
    gone.soft_delete!

    month = Date.current.beginning_of_month
    UsageCounter.create!(site_id: s1.site_id,   month: month, hit_count: 100)
    UsageCounter.create!(site_id: s2.site_id,   month: month, hit_count:  50)
    UsageCounter.create!(site_id: gone.site_id, month: month, hit_count: 999)

    assert_equal 150, user.hits_this_month
  end

  test "hits_this_month is 0 when user has no sites" do
    user = User.create!(email: "e@example.com")
    assert_equal 0, user.hits_this_month
  end

  test "regenerate_api_token! changes token" do
    user = User.create!(email: "f@example.com")
    old  = user.api_token
    user.regenerate_api_token!
    assert_not_equal old, user.api_token
    assert_match(/\Amcpa_/, user.api_token)
  end

  test "email_verified? reflects email_verified_at" do
    user = User.create!(email: "g@example.com")
    assert_not user.email_verified?
    user.update!(email_verified_at: Time.current)
    assert user.email_verified?
  end
end
