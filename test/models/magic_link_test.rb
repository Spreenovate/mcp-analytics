require "test_helper"

class MagicLinkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ml@example.com")
  end

  test "assigns token and 15-min expiry on create" do
    link = @user.magic_links.create!
    assert link.token.present?
    assert_in_delta 15.minutes.from_now.to_i, link.expires_at.to_i, 5
  end

  test "usable? toggles via mark_used!" do
    link = @user.magic_links.create!
    assert link.usable?
    link.mark_used!
    assert_not link.usable?
  end

  test "usable? false when expired" do
    link = @user.magic_links.create!(expires_at: 1.minute.ago)
    assert_not link.usable?
  end

  test "destroying user destroys magic_links" do
    @user.magic_links.create!
    assert_difference -> { MagicLink.count }, -1 do
      @user.destroy
    end
  end
end
