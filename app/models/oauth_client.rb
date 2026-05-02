class OauthClient < ApplicationRecord
  has_many :oauth_authorization_codes, dependent: :destroy
  has_many :oauth_access_tokens, dependent: :destroy
  has_many :oauth_authorization_requests, dependent: :destroy

  validates :client_id, presence: true, uniqueness: true
  validates :client_name, presence: true
  validates :redirect_uris, presence: true
  validate :redirect_uris_well_formed
  validate :token_endpoint_auth_method_supported

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

    list.each do |uri|
      parsed = URI.parse(uri.to_s)
      unless %w[http https].include?(parsed.scheme) || parsed.scheme == "claude" || parsed.scheme&.start_with?("cursor")
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
end
