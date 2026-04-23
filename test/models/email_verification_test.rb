require "test_helper"

class EmailVerificationTest < ActiveSupport::TestCase
  test "assigns verify_token, pending_user_id, expires_at on create" do
    v = EmailVerification.create!(email: "x@example.com")
    assert v.verify_token.present?
    assert_match(/\Apu_[a-z2-7]{8}\z/, v.pending_user_id)
    assert_in_delta 24.hours.from_now.to_i, v.expires_at.to_i, 5
  end

  test "usable? is true immediately, false after mark_used!" do
    v = EmailVerification.create!(email: "y@example.com")
    assert v.usable?
    v.mark_used!
    assert_not v.usable?
  end

  test "usable? is false after expiration" do
    v = EmailVerification.create!(email: "z@example.com", expires_at: 1.minute.ago)
    assert_not v.usable?
  end

  test "usable scope excludes used and expired" do
    fresh   = EmailVerification.create!(email: "a@example.com")
    used    = EmailVerification.create!(email: "b@example.com"); used.mark_used!
    expired = EmailVerification.create!(email: "c@example.com", expires_at: 1.minute.ago)

    scope = EmailVerification.usable
    assert_includes scope, fresh
    assert_not_includes scope, used
    assert_not_includes scope, expired
  end

  test "rejects invalid email format" do
    v = EmailVerification.new(email: "not-email")
    assert_not v.valid?
  end
end
