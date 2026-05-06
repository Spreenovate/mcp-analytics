class OauthClient < ApplicationRecord
  has_many :oauth_authorization_codes, dependent: :destroy
  has_many :oauth_access_tokens, dependent: :destroy
  has_many :oauth_authorization_requests, dependent: :destroy
  # Audit trail outlives the client itself (client may be removed but
  # the audit history of what happened with it is kept). Just nullify
  # the FK rather than destroy the row.
  has_many :oauth_audit_events, dependent: :nullify

  validates :client_id, presence: true, uniqueness: true
  validates :client_name, presence: true, length: { maximum: 100 }
  validates :client_uri, length: { maximum: 500 }, allow_nil: true
  validates :logo_uri,   length: { maximum: 500 }, allow_nil: true
  validates :redirect_uris, presence: true,
            length: { maximum: 4_000, message: "is too long (max 4000 chars total)" }
  validate :redirect_uris_well_formed
  validate :token_endpoint_auth_method_supported
  validate :info_uris_https_only

  MAX_REDIRECT_URIS = 5
  MAX_REDIRECT_URI_LENGTH = 500

  # Exact-match list of native schemes we recognise. NOT a prefix list:
  # `cursorevil://` and similar lookalikes must not pass.
  NATIVE_SCHEMES = %w[claude cursor].freeze

  before_validation :assign_client_id, on: :create

  SUPPORTED_AUTH_METHODS = %w[none].freeze
  SUPPORTED_GRANT_TYPES = %w[authorization_code].freeze
  SUPPORTED_RESPONSE_TYPES = %w[code].freeze

  def redirect_uri_list
    JSON.parse(redirect_uris.to_s)
  rescue JSON::ParserError
    []
  end

  def redirect_uri_list=(arr)
    self.redirect_uris = JSON.dump(Array(arr))
  end

  def allows_redirect_uri?(uri)
    return false if uri.blank?
    redirect_uri_list.include?(uri)
  end

  def self.generate_client_id
    "mcpa_client_#{SecureRandom.urlsafe_base64(12)}"
  end

  private

  def assign_client_id
    self.client_id ||= self.class.generate_client_id
  end

  def redirect_uris_well_formed
    list = redirect_uri_list
    if list.empty?
      errors.add(:redirect_uris, "must be a non-empty JSON array of URIs")
      return
    end
    if list.size > MAX_REDIRECT_URIS
      errors.add(:redirect_uris, "may contain at most #{MAX_REDIRECT_URIS} URIs")
      return
    end
    if list.any? { |uri| uri.to_s.length > MAX_REDIRECT_URI_LENGTH }
      errors.add(:redirect_uris, "individual URIs must be at most #{MAX_REDIRECT_URI_LENGTH} chars")
      return
    end

    list.each do |uri|
      parsed = URI.parse(uri.to_s)
      unless %w[http https].include?(parsed.scheme) || NATIVE_SCHEMES.include?(parsed.scheme)
        errors.add(:redirect_uris, "must be http(s) or a known native scheme; got #{uri.inspect}")
        return
      end
      if parsed.scheme == "http" && !%w[localhost 127.0.0.1].include?(parsed.host)
        errors.add(:redirect_uris, "http allowed only for localhost; got #{uri.inspect}")
        return
      end
      if uri.include?("#")
        errors.add(:redirect_uris, "must not contain a fragment; got #{uri.inspect}")
        return
      end
    rescue URI::InvalidURIError
      errors.add(:redirect_uris, "is not a valid URI: #{uri.inspect}")
    end
  end

  def token_endpoint_auth_method_supported
    return if SUPPORTED_AUTH_METHODS.include?(token_endpoint_auth_method)
    errors.add(:token_endpoint_auth_method, "must be one of #{SUPPORTED_AUTH_METHODS.inspect}")
  end

  # `client_uri` and `logo_uri` end up rendered (or linked from) the consent
  # screen. Reject http and javascript-style schemes to avoid hostile content.
  def info_uris_https_only
    %i[client_uri logo_uri].each do |attr|
      val = self[attr]
      next if val.blank?
      begin
        scheme = URI.parse(val).scheme
        unless scheme == "https"
          errors.add(attr, "must be https")
        end
      rescue URI::InvalidURIError
        errors.add(attr, "is not a valid URI")
      end
    end
  end
end
