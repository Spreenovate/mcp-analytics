module Oauth
  # Logs OAuth-relevant events for security review and the user-facing
  # connector activity log. All recorded events go through this single
  # entry point so the event vocabulary stays small and consistent.
  module Audit
    EVENTS = %w[
      client_registered
      consent_granted
      consent_denied
      token_issued
      token_refreshed
      token_revoked
    ].freeze

    # Cap the JSON-encoded metadata so a hostile DCR registrant can't
    # bloat the audit table via long client_name / redirect_uris / etc.
    MAX_METADATA_BYTES = 4096

    # Errors we deliberately swallow because audit must never block the
    # OAuth flow. Connection drops, deadlocks, locks-not-acquired are
    # operational issues, not bugs in our calling code.
    SWALLOWABLE = [
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::StatementInvalid,
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::Deadlocked,
      ActiveRecord::QueryCanceled
    ].freeze

    module_function

    def log(event, user: nil, oauth_client: nil, oauth_access_token: nil, request: nil, metadata: {})
      # ArgumentError on typos is a programmer-error: let it propagate so
      # tests + code-review catch it, never to be silently logged-and-lost.
      raise ArgumentError, "unknown event: #{event}" unless EVENTS.include?(event)

      OauthAuditEvent.create!(
        event: event,
        user: user,
        oauth_client: oauth_client,
        oauth_access_token: oauth_access_token,
        ip_address: request&.remote_ip,
        metadata_hash: cap(metadata)
      )
    rescue *SWALLOWABLE => e
      # Audit DB issues must never block the actual OAuth flow.
      Rails.logger.error("OAuth audit DB failed for #{event}: #{e.class}: #{e.message}")
      nil
    end

    # Truncate a hash's serialised form to MAX_METADATA_BYTES. We cap the
    # *encoded* size because that's what hits the column. If the raw
    # payload is already small enough, return it unchanged; otherwise
    # replace it with a marker so the audit row still records something.
    def cap(hash)
      hash ||= {}
      encoded = JSON.dump(hash)
      return hash if encoded.bytesize <= MAX_METADATA_BYTES
      { "_truncated" => true, "_original_bytes" => encoded.bytesize }
    end
  end
end
