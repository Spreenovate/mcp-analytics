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

  attr_reader :slug, :locale, :title, :description, :date, :hreflang_alt, :draft, :body_markdown, :mtime

  def self.all(locale: "en")
    return [] unless LOCALES.include?(locale)

    dir = POSTS_ROOT.join(locale)
    return [] unless dir.directory?

    posts = dir.glob("*.md").map { |path| from_path(path, locale: locale) }.compact
    posts = posts.reject(&:draft?) if Rails.env.production?
    posts.sort_by(&:date).reverse
  end

  SLUG_RE = /\A[a-z0-9][a-z0-9\-]*\z/

  def self.find(slug, locale: "en")
    return nil unless LOCALES.include?(locale) && slug =~ SLUG_RE

    path = POSTS_ROOT.join(locale, "#{slug}.md")
    return nil unless path.file?

    from_path(path, locale: locale)
  end

  def self.from_path(path, locale:)
    raw = path.read
    frontmatter, body = split_frontmatter(raw)
    return nil unless frontmatter

    slug = (frontmatter["slug"] || path.basename(".md").to_s).to_s
    return nil unless slug.match?(SLUG_RE)

    hreflang_alt = frontmatter["hreflang_alt"]
    return nil if hreflang_alt && !hreflang_alt.to_s.match?(SLUG_RE)

    new(
      slug: slug,
      locale: locale,
      title: frontmatter["title"],
      description: frontmatter["description"],
      date: frontmatter["date"].is_a?(Date) ? frontmatter["date"] : Date.parse(frontmatter["date"].to_s),
      hreflang_alt: hreflang_alt,
      draft: frontmatter["draft"] == true,
      body_markdown: body,
      mtime: path.mtime
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

  def initialize(slug:, locale:, title:, description:, date:, hreflang_alt:, draft:, body_markdown:, mtime: nil)
    @slug = slug
    @locale = locale
    @title = title
    @description = description
    @date = date
    @hreflang_alt = hreflang_alt
    @draft = draft
    @body_markdown = body_markdown
    @mtime = mtime
  end

  def draft? = @draft

  # Kramdown rendering is ~80-200ms per call on a 2500-word post. Cache
  # by mtime so an edit invalidates immediately on next request without
  # needing a manual cache bust.
  def body_html
    key = "blog_post/#{@locale}/#{@slug}/#{@mtime&.to_i || 0}/body_html"
    Rails.cache.fetch(key) do
      Kramdown::Document.new(
        @body_markdown,
        input: "GFM",
        hard_wrap: false,
        auto_ids: true,
        syntax_highlighter: nil
      ).to_html.html_safe
    end
  end

  def path
    @locale == "de" ? "/de/blog/#{@slug}" : "/blog/#{@slug}"
  end

  def hreflang_path
    return nil unless @hreflang_alt

    @locale == "de" ? "/blog/#{@hreflang_alt}" : "/de/blog/#{@hreflang_alt}"
  end

  # Best-available signal for sitemap lastmod. File mtime if the file
  # was edited after publication, otherwise the publication date.
  # NB: container builds (kamal/docker) reset mtime to build time, so
  # this is a useful signal in dev and a deploy-timestamp signal in
  # prod. Good enough for crawler recrawl heuristics either way.
  def lastmod_date
    return @date unless @mtime

    mtime_date = @mtime.to_date
    [ @date, mtime_date ].max
  end
end
