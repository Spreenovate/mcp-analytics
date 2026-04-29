class Site < ApplicationRecord
  PRIVACY_MODES = %w[strict balanced all].freeze
  # 'default' was the original name for 'balanced'. Accepted as input alias
  # so old MCP clients and existing prod rows keep working. Normalized to
  # 'balanced' at write time via the before_validation hook.
  PRIVACY_MODE_ALIASES = { "default" => "balanced" }.freeze
  SITE_ID_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567".freeze # Crockford-ish base32

  belongs_to :user

  validates :domain, presence: true
  validates :site_id, presence: true, uniqueness: true
  validates :privacy_mode, inclusion: { in: PRIVACY_MODES }
  validates :site_salt, presence: true

  before_validation :normalize_privacy_mode
  before_validation :assign_site_id, on: :create
  before_validation :assign_site_salt, on: :create

  scope :active, -> { where(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def active?
    deleted_at.nil?
  end

  def rotate_salt!
    update!(site_salt: SecureRandom.hex(16), salt_rotated_at: Time.current)
  end

  def self.generate_site_id
    chars = SITE_ID_ALPHABET.chars
    Array.new(8) { chars.sample }.join
  end

  private

  def normalize_privacy_mode
    return if privacy_mode.blank?
    self.privacy_mode = PRIVACY_MODE_ALIASES.fetch(privacy_mode, privacy_mode)
  end

  def assign_site_id
    return if site_id.present?

    loop do
      candidate = self.class.generate_site_id
      unless self.class.exists?(site_id: candidate)
        self.site_id = candidate
        break
      end
    end
  end

  def assign_site_salt
    self.site_salt ||= SecureRandom.hex(16)
  end
end
