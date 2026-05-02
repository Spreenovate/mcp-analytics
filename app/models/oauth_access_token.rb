class OauthAccessToken < ApplicationRecord
  VALID_FOR = 365.days
  TOKEN_PREFIX = "mcpa_oauth_".freeze

  belongs_to :user
  belongs_to :oauth_client

  validates :token, presence: true, uniqueness: true
  validates :scope, presence: true
  validates :expires_at, presence: true

  before_validation :assign_defaults, on: :create

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_used!
    update_column(:last_used_at, Time.current)
  end

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
  end

  private

  def assign_defaults
    self.token       ||= self.class.generate_token
    self.expires_at  ||= VALID_FOR.from_now
  end
end
