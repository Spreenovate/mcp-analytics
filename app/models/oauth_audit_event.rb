class OauthAuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :oauth_client, optional: true
  belongs_to :oauth_access_token, optional: true

  validates :event, presence: true

  # Append-only by intent — no updates, no deletes from app code. Don't
  # add update timestamps; reject mutation in callbacks so a stray
  # console-session can't silently rewrite the audit trail. (Records can
  # still vanish via `dependent: :destroy` on parent FKs — User/Client
  # deletion explicitly nullifies rather than destroys these rows.)
  self.record_timestamps = false
  before_validation -> { self.created_at ||= Time.current }, on: :create
  before_update   -> { raise ActiveRecord::ReadOnlyRecord, "OauthAuditEvent is append-only" }
  before_destroy  -> { raise ActiveRecord::ReadOnlyRecord, "OauthAuditEvent is append-only" }

  def metadata_hash
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def metadata_hash=(hash)
    self.metadata = JSON.dump(hash || {})
  end
end
