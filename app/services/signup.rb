# Shared signup logic used by both the Mcp::Tools#register_account MCP tool
# and the web-form-based SignupsController. Validates input, applies the
# anti-abuse rate limits, creates the EmailVerification, sends the mail.
#
# Returns a Result with one of:
#   status: :ok            verification present
#   status: :invalid       error_message present (bad email, disposable domain)
#   status: :rate_limited  error_message present (over per-IP / per-domain caps)
class Signup
  DISPOSABLE_DOMAINS = %w[
    10minutemail.com mailinator.com guerrillamail.com tempmail.com
    throwawaymail.com yopmail.com trashmail.com temp-mail.org
    getnada.com dropmail.me
  ].freeze

  Result = Struct.new(:status, :verification, :error_message, keyword_init: true) do
    def ok?           = status == :ok
    def invalid?      = status == :invalid
    def rate_limited? = status == :rate_limited
  end

  def self.start(email:, ip: nil, oauth_authorization_request: nil)
    email = email.to_s.strip.downcase

    return Result.new(status: :invalid, error_message: "Email required.")            if email.empty?
    return Result.new(status: :invalid, error_message: "Please enter a valid email.") unless email.match?(URI::MailTo::EMAIL_REGEXP)

    domain = email.split("@", 2)[1].to_s.downcase
    if DISPOSABLE_DOMAINS.include?(domain)
      return Result.new(status: :invalid, error_message: "Disposable email domains are not supported.")
    end

    ip = ip.to_s
    if ip.present?
      unless RateLimit.allow?(key: "reg:ip-h:#{ip}", limit: 3, window: 3600)
        return Result.new(status: :rate_limited, error_message: "Too many signups from your network. Try again in an hour.")
      end
      unless RateLimit.allow?(key: "reg:ip-d:#{ip}", limit: 10, window: 86_400)
        return Result.new(status: :rate_limited, error_message: "Too many signups from your network today.")
      end
    end

    unless RateLimit.allow?(key: "reg:dom-d:#{domain}", limit: 5, window: 86_400)
      return Result.new(status: :rate_limited, error_message: "Too many signups for this email domain today.")
    end

    verification = EmailVerification.create!(
      email: email,
      oauth_authorization_request: oauth_authorization_request
    )
    if oauth_authorization_request
      oauth_authorization_request.update!(email: email)
    end
    VerificationMailer.verify(verification).deliver_later
    Result.new(status: :ok, verification: verification)
  end
end
