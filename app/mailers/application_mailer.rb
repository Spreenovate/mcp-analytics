class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "no-reply@mcp-analytics.com")
  layout "mailer"
end
