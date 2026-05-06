module Oauth
  # Single source of truth for the OAuth scope vocabulary.
  #
  # `analytics:read`   - read site list and analytics queries
  # `analytics:manage` - add/remove sites (everything in :read plus writes)
  #
  # Naming follows the convention used by GitHub and others (resource:action
  # rather than action:resource) so the prefix tells you what's affected and
  # the suffix tells you what's allowed. The previous single scope was named
  # `read:analytics` but was actually granted account-wide write access via
  # add_site/remove_site -- intentionally renamed so the label matches the
  # capability.
  module Scopes
    READ    = "analytics:read".freeze
    MANAGE  = "analytics:manage".freeze
    ALL     = [ READ, MANAGE ].freeze
    DEFAULT = ALL.join(" ").freeze

    module_function

    # Parse a space-separated scope string into a Set of granted scopes,
    # dropping anything we don't recognise.
    def parse(str)
      str.to_s.split(/\s+/).select { |s| ALL.include?(s) }.to_set
    end

    def valid?(str)
      tokens = str.to_s.split(/\s+/)
      tokens.any? && tokens.all? { |s| ALL.include?(s) }
    end

    # Has the granted scope-string `granted` been issued at least
    # everything in `required`?
    def granted?(granted, required)
      g = parse(granted)
      Array(required).all? { |s| g.include?(s) }
    end
  end
end
