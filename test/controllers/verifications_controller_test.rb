require "test_helper"

class VerificationsControllerTest < ActionDispatch::IntegrationTest
  test "valid token creates user, marks verification used, shows page" do
    v = EmailVerification.create!(email: "verify@example.com")

    assert_difference -> { User.count }, 1 do
      get verify_path(token: v.verify_token)
    end
    assert_response :success

    user = User.find_by(email: "verify@example.com")
    assert user.email_verified?
    assert_includes response.body, user.api_token

    assert v.reload.used_at.present?
  end

  test "expired token renders :expired with 410" do
    v = EmailVerification.create!(email: "expired@example.com", expires_at: 1.hour.ago)
    get verify_path(token: v.verify_token)
    assert_response :gone
  end

  test "unknown token renders :expired with 410" do
    get verify_path(token: "totally-fake-token")
    assert_response :gone
  end

  test "second click on the same link surfaces existing user without re-creating" do
    v = EmailVerification.create!(email: "twice@example.com")
    get verify_path(token: v.verify_token)

    assert_no_difference -> { User.count } do
      get verify_path(token: v.verify_token)
    end
    assert_response :gone, "second hit should be 'expired' (already used)"
  end
end
