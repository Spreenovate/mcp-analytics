class OauthAuthorizationRequest < ApplicationRecord
  VALID_FOR = 30.minutes

  belongs_to :oauth_client
  belongs_to :user, optional: true
  has_one :email_verification, dependent: :nullify

  validates :request_token, presence: true, uniqueness: true
  validates :redirect_uri, presence: true
  validates :code_challenge, presence: true
  validates :code_challenge_method, presence: true,
            inclusion: { in: %w[S256] }
  validates :scope, presence: true
  validates :expires_at, presence: true

  before_validation :assign_defaults, on: :create

  scope :usable, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def usable?
    consumed_at.nil? && expires_at > Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def mark_consumed!
    update!(consumed_at: Time.current)
  end

  private

  def assign_defaults
    self.request_token ||= SecureRandom.urlsafe_base64(32)
    self.expires_at    ||= VALID_FOR.from_now
  end
end
