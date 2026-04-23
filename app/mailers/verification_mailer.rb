class VerificationMailer < ApplicationMailer
  def verify(verification)
    @verification = verification
    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    @verify_url = "#{@base_url}/verify/#{verification.verify_token}"

    mail(to: verification.email, subject: "Confirm your mcp-analytics account")
  end
end
