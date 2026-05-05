class User < ApplicationRecord
  PLAN_LIMITS = {
    "free" => 100_000
  }.freeze

  has_many :sites, dependent: :destroy
  has_many :oauth_access_tokens,           dependent: :destroy
  has_many :oauth_authorization_codes,     dependent: :destroy
  has_many :oauth_authorization_requests,  dependent: :destroy
  # Audit events are kept after user deletion for the OAuth client they
  # belonged to (the client may still be reviewed). Just null the FK.
  has_many :oauth_audit_events, dependent: :nullify

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :api_token, presence: true, uniqueness: true
  validates :plan, inclusion: { in: PLAN_LIMITS.keys }

  before_validation :assign_api_token, on: :create

  def active_sites
    sites.where(deleted_at: nil)
  end

  def plan_limit
    PLAN_LIMITS.fetch(plan)
  end

  def hits_this_month
    return 0 if active_sites.empty?

    UsageCounter.where(
      site_id: active_sites.pluck(:site_id),
      month: Date.current.beginning_of_month
    ).sum(:hit_count)
  end

  def email_verified?
    email_verified_at.present?
  end

  def regenerate_api_token!
    update!(api_token: self.class.generate_api_token)
  end

  def self.generate_api_token
    "mcpa_#{SecureRandom.urlsafe_base64(32)}"
  end

  private

  def assign_api_token
    self.api_token ||= self.class.generate_api_token
  end
end
