require "test_helper"

class RotateDefaultSaltsJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "salt@example.com")
  end

  test "rotates salts of balanced-mode sites older than 365 days" do
    stale = @user.sites.create!(domain: "stale.com", privacy_mode: "balanced",
                                salt_rotated_at: 400.days.ago)
    old_salt = stale.site_salt

    RotateDefaultSaltsJob.perform_now

    assert_not_equal old_salt, stale.reload.site_salt
    assert stale.salt_rotated_at > 1.minute.ago
  end

  test "does NOT rotate strict-mode sites (they use daily salt in-process)" do
    strict = @user.sites.create!(domain: "strict.com", privacy_mode: "strict",
                                 salt_rotated_at: 400.days.ago)
    old_salt = strict.site_salt

    RotateDefaultSaltsJob.perform_now

    assert_equal old_salt, strict.reload.site_salt
  end

  test "does NOT rotate all-mode sites (visitor_id is cookie-backed, persistence is the feature)" do
    allsite = @user.sites.create!(domain: "all.com", privacy_mode: "all",
                                  salt_rotated_at: 400.days.ago)
    old_salt = allsite.site_salt

    RotateDefaultSaltsJob.perform_now

    assert_equal old_salt, allsite.reload.site_salt
  end

  test "leaves balanced-mode sites younger than 365 days alone" do
    fresh = @user.sites.create!(domain: "fresh.com", privacy_mode: "balanced",
                                salt_rotated_at: 30.days.ago)
    old_salt = fresh.site_salt

    RotateDefaultSaltsJob.perform_now

    assert_equal old_salt, fresh.reload.site_salt
  end
end
