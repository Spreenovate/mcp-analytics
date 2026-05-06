# Shared signup logic used by both the landing-form (SignupsController)
# and the OAuth authorize flow (Oauth::AuthorizationsController#start).
# Validates input, applies the anti-abuse rate limits, creates the
# EmailVerification, sends the mail.
#
# Returns a Result with one of:
#   status: :ok            verification present
#   status: :invalid       error_message present (format-only feedback)
#   status: :rate_limited  generic error_message (anti-enumeration); the
#                          specific reason is in `reason` for server-side
#                          logging/metrics, never echoed to the user.
#
# Why the disposable check returns :rate_limited with a generic message:
# the disposable list, the per-IP caps, and the per-email-domain cap are
# all attacker-controlled inputs. If we returned distinct user-visible
# strings ("disposable" vs "domain rate-limited" vs "ip rate-limited"),
# the public-reachable `/oauth/authorize/start` path becomes a domain-
# enumeration oracle. Single generic message, real reason only in logs.
class Signup
  DISPOSABLE_DOMAINS = %w[
    10minutemail.com mailinator.com guerrillamail.com tempmail.com
    throwawaymail.com yopmail.com trashmail.com temp-mail.org
    getnada.com dropmail.me
  ].freeze

  GENERIC_BLOCKED_MESSAGE =
    "We couldn't send the verification mail. Try again later or use a different email."

  Result = Struct.new(:status, :verification, :error_message, :reason, keyword_init: true) do
    def ok?           = status == :ok
    def invalid?      = status == :invalid
    def rate_limited? = status == :rate_limited
  end

  def self.start(email:, ip: nil, oauth_authorization_request: nil)
    email = email.to_s.strip.downcase

    return blocked(:empty_email,   "Email required.",            status: :invalid) if email.empty?
    return blocked(:invalid_email, "Please enter a valid email.", status: :invalid) unless email.match?(URI::MailTo::EMAIL_REGEXP)

    domain = email.split("@", 2)[1].to_s.downcase
    return blocked(:disposable, GENERIC_BLOCKED_MESSAGE) if DISPOSABLE_DOMAINS.include?(domain)

    ip = ip.to_s
    if ip.present?
      return blocked(:ip_hour, GENERIC_BLOCKED_MESSAGE) unless RateLimit.allow?(key: "reg:ip-h:#{ip}", limit: 3, window: 3600)
      return blocked(:ip_day,  GENERIC_BLOCKED_MESSAGE) unless RateLimit.allow?(key: "reg:ip-d:#{ip}", limit: 10, window: 86_400)
    end

    return blocked(:domain_day, GENERIC_BLOCKED_MESSAGE) unless RateLimit.allow?(key: "reg:dom-d:#{domain}", limit: 5, window: 86_400)

    verification = EmailVerification.create!(
      email: email,
      oauth_authorization_request: oauth_authorization_request
    )
    if oauth_authorization_request
      oauth_authorization_request.update!(email: email)
    end
    VerificationMailer.verify(verification).deliver_later
    Result.new(status: :ok, verification: verification, reason: :ok)
  end

  def self.blocked(reason, message, status: :rate_limited)
    Rails.logger.info("[Signup] blocked reason=#{reason}")
    Result.new(status: status, error_message: message, reason: reason)
  end
  private_class_method :blocked
end
