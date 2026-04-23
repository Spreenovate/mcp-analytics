class EmailVerification < ApplicationRecord
  VALID_FOR = 24.hours

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :verify_token, presence: true, uniqueness: true
  validates :pending_user_id, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :assign_tokens, on: :create

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def usable?
    used_at.nil? && expires_at > Time.current
  end

  def mark_used!
    update!(used_at: Time.current)
  end

  private

  def assign_tokens
    self.verify_token    ||= SecureRandom.urlsafe_base64(32)
    self.pending_user_id ||= "pu_#{Site.generate_site_id}"
    self.expires_at      ||= VALID_FOR.from_now
  end
end
