require "test_helper"

class SignupTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @prev_cache
  end

  # --- format validation -------------------------------------------------

  test "empty email -> :invalid with empty_email reason" do
    r = Signup.start(email: "", ip: "1.2.3.4")
    assert r.invalid?
    assert_equal :empty_email, r.reason
    assert_match(/required/i, r.error_message)
  end

  test "malformed email -> :invalid with invalid_email reason" do
    r = Signup.start(email: "not-an-email", ip: "1.2.3.4")
    assert r.invalid?
    assert_equal :invalid_email, r.reason
    assert_match(/valid email/i, r.error_message)
  end

  # --- anti-enumeration: all four abuse buckets share the SAME message ---

  test "disposable domain returns generic message (no domain enumeration)" do
    r = Signup.start(email: "x@mailinator.com", ip: "1.2.3.4")
    assert r.rate_limited?
    assert_equal :disposable, r.reason
    assert_equal Signup::GENERIC_BLOCKED_MESSAGE, r.error_message
  end

  test "ip-hour limit (3/IP/hour) returns generic message" do
    3.times { |i| Signup.start(email: "u#{i}@example.com", ip: "10.0.0.1") }
    r = Signup.start(email: "u4@example.com", ip: "10.0.0.1")
    assert r.rate_limited?
    assert_equal :ip_hour, r.reason
    assert_equal Signup::GENERIC_BLOCKED_MESSAGE, r.error_message
  end

  test "ip-day limit (10/IP/day) returns generic message" do
    # Burn through 3/IP/hour first → wait virtually, refill via 10 distinct
    # domains in distinct hours? We can't time-travel cheaply. Instead test
    # by stubbing only the ip-h check to allow, then exhausting ip-d.
    stub_ratelimit(only_real: [ /\Areg:ip-d:/ ]) do
      10.times { |i| Signup.start(email: "u#{i}@example.com", ip: "10.0.0.2") }
      r = Signup.start(email: "u11@example.com", ip: "10.0.0.2")
      assert r.rate_limited?
      assert_equal :ip_day, r.reason
      assert_equal Signup::GENERIC_BLOCKED_MESSAGE, r.error_message
    end
  end

  test "domain-day limit (5/domain/day) returns generic message — distinct IPs" do
    5.times do |i|
      Signup.start(email: "x#{i}@onedomain.com", ip: "10.0.1.#{i}")
    end
    r = Signup.start(email: "x6@onedomain.com", ip: "10.0.1.99")
    assert r.rate_limited?
    assert_equal :domain_day, r.reason
    assert_equal Signup::GENERIC_BLOCKED_MESSAGE, r.error_message
  end

  test "all four abuse buckets return identical user-visible message" do
    msgs = [
      Signup.start(email: "x@mailinator.com", ip: "1.1.1.1").error_message
    ]
    4.times { |i| Signup.start(email: "u#{i}@a.com", ip: "1.1.1.2") }
    msgs << Signup.start(email: "u4@a.com", ip: "1.1.1.2").error_message
    assert_equal 1, msgs.uniq.size,
      "abuse-bucket messages must be indistinguishable; got: #{msgs.uniq.inspect}"
  end

  # --- happy path --------------------------------------------------------

  test "valid email + clean IP creates verification and queues mail" do
    assert_difference -> { EmailVerification.count }, 1 do
      assert_enqueued_emails 1 do
        r = Signup.start(email: "fresh@example.com", ip: "192.0.2.1")
        assert r.ok?
        assert_equal :ok, r.reason
      end
    end
  end

  private

  # Isolates one rate-limit bucket so the other buckets can't fire first.
  # `only_real:` is an array of regexes; keys matching those go through
  # the real RateLimit. All other keys auto-allow.
  def stub_ratelimit(only_real:)
    original = RateLimit.method(:allow?)
    RateLimit.singleton_class.define_method(:allow?) do |key:, **kw|
      next original.call(key: key, **kw) if only_real.any? { |re| key.match?(re) }
      true
    end
    yield
  ensure
    RateLimit.singleton_class.define_method(:allow?, original)
  end
end
