require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  test "POST /signup with valid email creates verification, queues mail, redirects to /signup/check" do
    assert_difference -> { EmailVerification.count }, 1 do
      assert_enqueued_emails 1 do
        post signup_path, params: { email: "founder@example.com" }
      end
    end
    assert_redirected_to signup_check_path
  end

  test "POST /signup with invalid email redirects with alert" do
    assert_no_difference -> { EmailVerification.count } do
      post signup_path, params: { email: "not-an-email" }
    end
    assert_redirected_to root_path(anchor: "signup-form")
    assert flash[:alert].present?
  end

  test "POST /signup with disposable email is rejected with generic message (no enumeration)" do
    post signup_path, params: { email: "spam@mailinator.com" }
    assert_redirected_to root_path(anchor: "signup-form")
    assert_match(/couldn't send/i, flash[:alert])
    assert_no_match(/disposable|mailinator/i, flash[:alert])
  end

  test "POST /signup is rate-limited (3/IP/hour) with generic message" do
    3.times do |i|
      post signup_path, params: { email: "u#{i}@example.com" }
    end
    post signup_path, params: { email: "u4@example.com" }
    assert_redirected_to root_path(anchor: "signup-form")
    assert_match(/couldn't send/i, flash[:alert])
    assert_no_match(/network|ip/i, flash[:alert])
  end

  test "GET /signup/check renders when session has email" do
    post signup_path, params: { email: "show-check@example.com" }
    follow_redirect!
    assert_response :success
    assert_includes response.body, "show-check@example.com"
  end

  test "GET /signup/check redirects home if no session" do
    get signup_check_path
    assert_redirected_to root_path
  end
end
