require "yaml"
require "kramdown"
require "kramdown-parser-gfm"

# Loads a markdown post from app/views/blog/posts/{locale}/{slug}.md.
# Pure PORO, no ActiveRecord — content lives in git, not the database.
# Same model serves /blog (locale=en) and /de/blog (locale=de).
#
# Expected frontmatter:
#   ---
#   title: "..."         # required
#   description: "..."   # required, used as <meta description>
#   date: 2026-05-19     # required, used for sort + display
#   slug: claude-mcp-setup  # optional, derived from filename if omitted
#   hreflang_alt: "..."  # optional, slug of the same-content post in the other locale
#   draft: true          # optional, hides from index in production
#   ---
#
# Convention: never use a single `#` heading inside the body — the page
# title is rendered separately by the layout. Body must start at `##`.
class BlogPost
  LOCALES = %w[en de].freeze
  POSTS_ROOT = Rails.root.join("app/views/blog/posts")

  attr_reader :slug, :locale, :title, :description, :date, :hreflang_alt, :draft, :body_markdown

  def self.all(locale: "en")
    return [] unless LOCALES.include?(locale)

    dir = POSTS_ROOT.join(locale)
    return [] unless dir.directory?

    posts = dir.glob("*.md").map { |path| from_path(path, locale: locale) }.compact
    posts = posts.reject(&:draft?) if Rails.env.production?
    posts.sort_by(&:date).reverse
  end

  def self.find(slug, locale: "en")
    return nil unless LOCALES.include?(locale) && slug =~ /\A[a-z0-9][a-z0-9\-]*\z/

    path = POSTS_ROOT.join(locale, "#{slug}.md")
    return nil unless path.file?

    from_path(path, locale: locale)
  end

  def self.from_path(path, locale:)
    raw = path.read
    frontmatter, body = split_frontmatter(raw)
    return nil unless frontmatter

    new(
      slug: frontmatter["slug"] || path.basename(".md").to_s,
      locale: locale,
      title: frontmatter["title"],
      description: frontmatter["description"],
      date: frontmatter["date"].is_a?(Date) ? frontmatter["date"] : Date.parse(frontmatter["date"].to_s),
      hreflang_alt: frontmatter["hreflang_alt"],
      draft: frontmatter["draft"] == true,
      body_markdown: body
    )
  rescue StandardError => e
    Rails.logger.warn("BlogPost: failed to parse #{path}: #{e.class} #{e.message}")
    nil
  end

  def self.split_frontmatter(raw)
    return [ nil, nil ] unless raw.start_with?("---\n")

    parts = raw.split(/^---\s*$/, 3)
    return [ nil, nil ] if parts.length < 3

    [ YAML.safe_load(parts[1], permitted_classes: [ Date, Time ]), parts[2].strip ]
  end

  def initialize(slug:, locale:, title:, description:, date:, hreflang_alt:, draft:, body_markdown:)
    @slug = slug
    @locale = locale
    @title = title
    @description = description
    @date = date
    @hreflang_alt = hreflang_alt
    @draft = draft
    @body_markdown = body_markdown
  end

  def draft? = @draft

  def body_html
    Kramdown::Document.new(
      @body_markdown,
      input: "GFM",
      hard_wrap: false,
      auto_ids: true,
      syntax_highlighter: nil
    ).to_html.html_safe
  end

  def path
    @locale == "de" ? "/de/blog/#{@slug}" : "/blog/#{@slug}"
  end

  def hreflang_path
    return nil unless @hreflang_alt

    @locale == "de" ? "/blog/#{@hreflang_alt}" : "/de/blog/#{@hreflang_alt}"
  end
end
