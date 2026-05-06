# Drive an integration test through the verify-link flow so subsequent
# requests are authenticated as the user. Mirrors the real signed-in
# state — sets the same cookie a browser would carry.
#
# Block 5 split GET /verify (renders confirmation form, no state change)
# from POST /verify (does the actual sign-in). The helper does both
# steps just like a real user would.
module SettingsSessionHelper
  def sign_in_via_verify(email)
    v = EmailVerification.create!(email: email)
    # GET is intentionally a no-op state-wise — that's the Block-5
    # CSRF defence. Only POST mutates state and establishes the
    # session.
    get verify_path(token: v.verify_token)
    post verify_confirm_path(token: v.verify_token)
    User.find_by(email: email)
  end
end
