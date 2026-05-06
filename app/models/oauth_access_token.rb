class OauthAccessToken < ApplicationRecord
  # OAuth 2.1 / MCP-spec recommends short-lived access tokens with
  # refresh-token rotation. Defaults from Block 4 onwards:
  #   - access_token  expires after 24h
  #   - refresh_token expires after 90d (idle timeout — every refresh
  #                    extends the window)
  # Pre-Block-4 tokens were issued with VALID_FOR=365.days and no refresh;
  # those rows are honoured as-is until they expire.
  VALID_FOR         = 24.hours
  REFRESH_VALID_FOR = 90.days
  TOKEN_PREFIX         = "mcpa_oauth_".freeze
  REFRESH_TOKEN_PREFIX = "mcpa_refresh_".freeze

  belongs_to :user
  belongs_to :oauth_client
  has_many :oauth_audit_events, dependent: :nullify

  validates :token, presence: true, uniqueness: true
  validates :refresh_token, uniqueness: true, allow_nil: true
  validates :scope, presence: true
  validates :expires_at, presence: true
  # RFC 8707 audience binding: every access token MUST be bound to a
  # resource. The pre-Block-3 nil-resource grandfather slot is removed by
  # the 20260507100001 backfill migration; the validation keeps it closed.
  validates :resource, presence: true

  before_validation :assign_defaults, on: :create

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :with_active_refresh, -> {
    where(revoked_at: nil, refresh_token_used_at: nil)
      .where("refresh_token_expires_at > ?", Time.current)
  }

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  # Used at /oauth/token (grant_type=refresh_token) — distinct from
  # access-token validity (`active?`). A refresh is usable iff:
  #   - it exists (refresh_token != nil)
  #   - the row isn't revoked
  #   - this refresh value hasn't been redeemed yet (rotation)
  #   - it hasn't aged out
  def refresh_active?
    refresh_token.present? &&
      revoked_at.nil? &&
      refresh_token_used_at.nil? &&
      refresh_token_expires_at.present? &&
      refresh_token_expires_at > Time.current
  end

  # Kills both halves of the access/refresh pair. Without consuming the
  # refresh side, a token revoked via the Settings UI would still match
  # the refresh-token redemption path and silently fall into
  # `:inactive_refresh` instead of producing a `:replay` audit signal —
  # the operator loses the alerting hook for "stolen refresh used after
  # user revoked the connector". One method, one source of truth.
  def revoke!
    now = Time.current
    update!(revoked_at: now,
            refresh_token_used_at: refresh_token_used_at || now)
  end

  # Stamps `last_used_at` no more than once per `threshold` seconds, so a
  # high-rate MCP client (Claude polling tools/list, batch-RPC, etc.)
  # doesn't write a row per call. The exact-time precision was never
  # needed — Settings UI shows "Last used 5 minutes ago" granularity
  # anyway, and the audit log carries per-request precision when we need
  # it.
  TOUCH_USED_THROTTLE = 60.seconds

  def touch_used!(now: Time.current)
    return if last_used_at && now - last_used_at < TOUCH_USED_THROTTLE
    update_column(:last_used_at, now)
  end

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
  end

  def self.generate_refresh_token
    "#{REFRESH_TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
  end

  private

  def assign_defaults
    self.token                    ||= self.class.generate_token
    self.expires_at               ||= VALID_FOR.from_now
    self.refresh_token            ||= self.class.generate_refresh_token
    self.refresh_token_expires_at ||= REFRESH_VALID_FOR.from_now
    # RFC 8707: every token must carry a resource. Default to canonical
    # so console / test creators don't trip the validation, but keep the
    # validation so an explicit `resource: nil` still fails loudly.
    self.resource                 ||= Oauth::BaseUrl.canonical_resource
  end
end
