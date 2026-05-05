# Drive an integration test through the verify-link flow so subsequent
# requests are authenticated as the user. Mirrors the real signed-in
# state — sets the same cookie a browser would carry.
module SettingsSessionHelper
  def sign_in_via_verify(email)
    v = EmailVerification.create!(email: email)
    get verify_path(token: v.verify_token)
    User.find_by(email: email)
  end
end
