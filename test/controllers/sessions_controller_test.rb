require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(email: "ml@example.com", email_verified_at: Time.current)
  end

  teardown do
    Rails.cache = @prev_cache
  end

  test "GET /login renders the form" do
    get login_path
    assert_response :success
  end

  test "POST /magic-link queues mailer for known user and renders check_email" do
    assert_difference -> { @user.magic_links.count }, 1 do
      assert_enqueued_emails 1 do
        post magic_link_path, params: { email: @user.email }
      end
    end
    assert_response :success
  end

  test "POST /magic-link for unknown email still renders check_email but sends nothing" do
    assert_no_difference -> { MagicLink.count } do
      assert_enqueued_emails 0 do
        post magic_link_path, params: { email: "ghost@example.com" }
      end
    end
    assert_response :success
  end

  test "POST /magic-link enforces 5/email/hour limit" do
    5.times { post magic_link_path, params: { email: @user.email } }
    assert_no_difference -> { MagicLink.count } do
      post magic_link_path, params: { email: @user.email }
    end
  end

  test "GET /auth/:token logs the user in and redirects to settings" do
    link = @user.magic_links.create!
    get auth_path(token: link.token)
    assert_redirected_to settings_path
    assert link.reload.used_at.present?
  end

  test "expired magic-link token returns 410" do
    link = @user.magic_links.create!(expires_at: 1.minute.ago)
    get auth_path(token: link.token)
    assert_response :gone
  end

  test "unknown magic-link token returns 410" do
    get auth_path(token: "missing")
    assert_response :gone
  end
end

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "settings@example.com", email_verified_at: Time.current)
    link = @user.magic_links.create!
    get auth_path(token: link.token) # establishes session
  end

  test "GET /settings shows account info to a logged-in user" do
    @user.sites.create!(domain: "example.com", privacy_mode: "strict")
    get settings_path
    assert_response :success
    assert_includes response.body, @user.email
    assert_includes response.body, "example.com"
  end

  test "GET /settings without session redirects to /login" do
    reset!
    get settings_path
    assert_redirected_to login_path
  end

  test "POST /settings/regenerate-token rotates the API token" do
    old = @user.api_token
    post regenerate_token_settings_path
    assert_redirected_to settings_path
    assert_not_equal old, @user.reload.api_token
  end

  test "DELETE /settings/delete-account destroys the user and clears session" do
    assert_difference -> { User.count }, -1 do
      delete destroy_account_settings_path
    end
    assert_redirected_to root_path
  end
end
