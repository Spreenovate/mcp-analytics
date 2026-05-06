class PruneOauthAuditEventsJob < ApplicationJob
  queue_as :default

  # Retention for the OAuth audit trail. 90 days is enough for security
  # review, customer support requests ("when did Claude connect?"), and
  # the directory-submission "prove user authorised this client" use
  # case. Keeping more is unbounded growth — clients_registered alone
  # generates a row per DCR call.
  #
  # Uses delete_all to bypass the model's append-only callbacks. Those
  # protect against app-code mutation, not against retention pruning,
  # which is operations.
  RETENTION_PERIOD = 90.days

  def perform
    cutoff  = RETENTION_PERIOD.ago
    deleted = OauthAuditEvent.where("created_at < ?", cutoff).delete_all
    Rails.logger.info("[oauth_audit_pruning] deleted=#{deleted} cutoff=#{cutoff.iso8601}")
  end
end
