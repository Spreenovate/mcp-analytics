class OperatorMailer < ApplicationMailer
  default from: ENV.fetch("MAIL_FROM", "no-reply@mcp-analytics.com")

  def usage_alert(user:, hits:)
    @user = user
    @hits = hits
    mail(to: ENV.fetch("OPERATOR_EMAIL", "alex@mcp-analytics.com"),
         subject: "[mcp-analytics] #{user.email} crossed 150% of plan limit")
  end
end
