class MagicLinkMailer < ApplicationMailer
  def sign_in(magic_link)
    @magic_link = magic_link
    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    @url = "#{@base_url}/auth/#{magic_link.token}"

    mail(to: magic_link.user.email, subject: "Your mcp-analytics sign-in link")
  end
end
