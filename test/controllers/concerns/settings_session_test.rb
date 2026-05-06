require "test_helper"

# Drive the SettingsSession concern through a stub controller so we can
# poke session-state edge cases (future-dated seen_at, exact-expiry
# boundary, version mismatch) directly.
class SettingsSessionTest < ActiveSupport::TestCase
  class FakeController
    # `helper_method` is provided by ActionController::Base — stub it so
    # the SettingsSession concern can be included into a plain Ruby class.
    def self.helper_method(*); end

    include SettingsSession

    attr_accessor :session, :flash, :redirected_to

    def initialize(session: {})
      @session = session
      @flash = {}
    end

    def reset_session
      @session = {}
    end

    def redirect_to(path, options = {})
      @redirected_to = path
      @flash.merge!(options)
    end

    def root_path
      "/"
    end
  end

  setup do
    @user = User.create!(email: "concern@example.com", email_verified_at: Time.current)
  end

  test "lookup returns user on a freshly signed-in session" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    assert_equal @user.id, c.current_settings_user.id
  end

  test "lookup returns nil when session is empty" do
    c = FakeController.new
    assert_nil c.current_settings_user
  end

  test "lookup nils out + resets when seen_at is in the future (forged/corrupted cookie)" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    c.session[:settings_seen_at] = (Time.current + 1.hour).to_i
    c.instance_variable_set(:@current_settings_user, nil) # bust the memo
    c.remove_instance_variable(:@current_settings_user) if c.instance_variable_defined?(:@current_settings_user)

    assert_nil c.current_settings_user
    assert_empty c.session, "future-dated seen_at must trigger reset_session"
  end

  test "lookup nils out when idle longer than IDLE_TIMEOUT" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    c.session[:settings_seen_at] = (Time.current - SettingsSession::IDLE_TIMEOUT - 1.minute).to_i

    assert_nil c.current_settings_user
    assert_empty c.session
  end

  test "lookup nils out when session_version no longer matches the user's" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    @user.bump_session_version!

    assert_nil c.current_settings_user
    assert_empty c.session
  end

  test "lookup slides the seen_at timestamp on each call" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    initial = c.session[:settings_seen_at]

    travel 5.minutes do
      c.current_settings_user
      assert_operator c.session[:settings_seen_at], :>, initial
    end
  end

  test "sign_out_of_settings bumps user.session_version" do
    c = FakeController.new
    c.sign_in_for_settings(@user)
    original = @user.session_version

    c.sign_out_of_settings
    assert_operator @user.reload.session_version, :>, original
    assert_empty c.session
  end

  test "sign_in regenerates session id (defeats fixation)" do
    c = FakeController.new(session: { fingerprint: "old-attacker-value" })
    c.sign_in_for_settings(@user)

    assert_nil c.session[:fingerprint], "reset_session must drop pre-existing keys"
    assert_equal @user.id, c.session[:settings_user_id]
  end

  test "sign_out clears local session even if version-bump fails (Block 3 ordering)" do
    c = FakeController.new
    c.session[:settings_user_id]      = @user.id
    c.session[:settings_user_version] = @user.session_version
    c.session[:settings_seen_at]      = Time.current.to_i

    # Override current_settings_user to return a user whose bump raises.
    doctored = @user
    doctored.define_singleton_method(:bump_session_version!) do
      raise ActiveRecord::ConnectionNotEstablished, "simulated db outage"
    end
    c.define_singleton_method(:current_settings_user) { doctored }

    assert_nothing_raised { c.sign_out_of_settings }
    assert_empty c.session, "local session must be reset before bump runs"
  end
end
