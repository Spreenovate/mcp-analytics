class OauthAuthorizationCode < ApplicationRecord
  VALID_FOR = 10.minutes

  belongs_to :user
  belongs_to :oauth_client

  validates :code, presence: true, uniqueness: true
  validates :redirect_uri, presence: true
  validates :scope, presence: true
  validates :code_challenge, presence: true
  validates :code_challenge_method, presence: true,
            inclusion: { in: %w[S256] }
  validates :expires_at, presence: true

  before_validation :assign_defaults, on: :create

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def usable?
    used_at.nil? && expires_at > Time.current
  end

  def mark_used!
    update!(used_at: Time.current)
  end

  # PKCE check per RFC 7636 §4.6 (S256)
  def verify_pkce!(code_verifier)
    return false if code_verifier.to_s.empty?

    expected = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier),
      padding: false
    )
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end

  def self.generate_code
    SecureRandom.urlsafe_base64(32)
  end

  private

  def assign_defaults
    self.code        ||= self.class.generate_code
    self.expires_at  ||= VALID_FOR.from_now
  end
end
