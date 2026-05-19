# Programmatic /mcp/tools/{slug} pages, auto-populated from the canonical
# tool list in Mcp::ToolSchemas::AUTHENTICATED. No database, no markdown
# — the source of truth is the same schema file the MCP server itself
# uses, so the page can't drift from reality.
#
# Optional per-tool prose (intro paragraph, example prompts, example
# output) lives in app/views/mcp_tools/_examples/{slug}.html.erb. If
# absent the page still renders with the schema-driven defaults.
class McpToolPage
  attr_reader :name, :title, :description, :input_schema, :scope, :annotations

  GROUPS = {
    "overview"   => %w[get_overview get_timeseries compare_periods],
    "discovery"  => %w[top_pages top_referrers top_sources list_events event_details],
    "audience"   => %w[breakdown top_languages top_timezones top_user_agents traffic_class_breakdown viewport_breakdown color_scheme_breakdown],
    "engagement" => %w[engagement_overview],
    "sites"      => %w[list_sites add_site remove_site get_tracking_snippet],
    "account"    => %w[get_account regenerate_api_token],
    "onboarding" => %w[get_started_guide]
  }.freeze

  def self.all
    Mcp::ToolSchemas::AUTHENTICATED.map { |schema| new(schema) }
  end

  def self.find(slug)
    return nil unless slug =~ /\A[a-z0-9][a-z0-9_]*\z/

    schema = Mcp::ToolSchemas::AUTHENTICATED.find { |s| s[:name] == slug }
    schema && new(schema)
  end

  def self.grouped
    GROUPS.transform_values { |names| names.map { |n| find(n) }.compact }
  end

  def initialize(schema)
    @name = schema[:name]
    @title = schema[:title]
    @description = schema[:description]
    @input_schema = schema[:inputSchema] || {}
    @scope = schema[:scope]
    @annotations = schema[:annotations] || {}
  end

  def slug = @name.tr("_", "-")
  def path = "/mcp/tools/#{slug}"

  def read_only?
    @annotations[:readOnlyHint] == true
  end

  def destructive?
    @annotations[:destructiveHint] == true
  end

  def required_args
    Array(@input_schema[:required])
  end

  def args
    (@input_schema[:properties] || {}).map do |name, spec|
      {
        name: name.to_s,
        required: required_args.include?(name.to_s),
        type: Array(spec[:type]).first,
        enum: spec[:enum],
        default: spec[:default],
        description: spec[:description]
      }
    end
  end

  # Short one-liner derived from the first sentence of `description`.
  # Used as <meta description> and intro line.
  def summary
    @description.to_s.split(/(?<=[.!?])\s/).first.to_s.strip
  end

  # Examples partial. Returns the partial path if a file exists, else nil.
  def example_partial
    candidate = Rails.root.join("app/views/mcp_tools/_examples/_#{slug}.html.erb")
    candidate.file? ? "mcp_tools/examples/#{slug}" : nil
  end
end
