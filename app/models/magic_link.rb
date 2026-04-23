class MagicLink < ApplicationRecord
  VALID_FOR = 15.minutes

  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :assign_token, on: :create

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def usable?
    used_at.nil? && expires_at > Time.current
  end

  def mark_used!
    update!(used_at: Time.current)
  end

  private

  def assign_token
    self.token      ||= SecureRandom.urlsafe_base64(32)
    self.expires_at ||= VALID_FOR.from_now
  end
end
