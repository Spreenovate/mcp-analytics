require "test_helper"

class SiteTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "site-owner@example.com")
  end

  test "auto-generates site_id and site_salt" do
    site = @user.sites.create!(domain: "example.com", privacy_mode: "strict")
    assert_equal 8, site.site_id.length
    assert_match(/\A[a-z2-7]{8}\z/, site.site_id)
    assert_equal 32, site.site_salt.length
  end

  test "rejects invalid privacy_mode" do
    site = @user.sites.build(domain: "example.com", privacy_mode: "maximum")
    assert_not site.valid?
  end

  test "accepts each valid privacy_mode" do
    Site::PRIVACY_MODES.each do |mode|
      site = @user.sites.create!(domain: "#{mode}.com", privacy_mode: mode)
      assert_equal mode, site.privacy_mode
    end
  end

  test "soft_delete! sets deleted_at and removes from active scope" do
    site = @user.sites.create!(domain: "soft.com", privacy_mode: "strict")
    assert site.active?
    site.soft_delete!
    assert_not site.active?
    assert_not_includes Site.active, site
  end

  test "rotate_salt! changes salt and sets timestamp" do
    site = @user.sites.create!(domain: "r.com", privacy_mode: "balanced")
    old_salt = site.site_salt
    freeze_time do
      site.rotate_salt!
      assert_not_equal old_salt, site.site_salt
      assert_equal Time.current, site.salt_rotated_at
    end
  end

  test "site_id is unique across sites" do
    ids = 5.times.map { @user.sites.create!(domain: SecureRandom.hex(4) + ".com", privacy_mode: "strict").site_id }
    assert_equal ids.uniq.length, ids.length
  end

  test "generate_site_id returns 8 base32 chars" do
    assert_match(/\A[a-z2-7]{8}\z/, Site.generate_site_id)
  end
end
