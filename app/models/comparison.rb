require "yaml"
require "kramdown"
require "kramdown-parser-gfm"

# Loads a /vs/{competitor} comparison page from
# app/views/comparisons/{locale}/{slug}.md.
#
# Same parsing rules as BlogPost — but the frontmatter shape is different
# because comparison pages render a structured table block in addition to
# free-form markdown. Frontmatter columns:
#   ---
#   competitor: "Plausible"
#   competitor_url: "https://plausible.io"
#   slug: plausible
#   title: "mcp-analytics vs Plausible (2026)"
#   description: "..."
#   date: 2026-05-19
#   table:
#     - feature: "Free tier"
#       us: "100k hits/mo, unlimited sites"
#       them: "30-day trial, no free"
#     - feature: "Price (paid entry)"
#       us: "€19/mo, 10M hits"
#       them: "$9/mo, 10k pageviews"
#   verdict_us: "Best when you want analytics inside Claude/Cursor."
#   verdict_them: "Best when you want a beautiful dashboard your team can open."
#   hreflang_alt: "plausible-vergleich"
#   ---
#
# Body markdown below the frontmatter renders below the table, used for
# detailed reasoning, code snippets, and honest caveats.
class Comparison
  LOCALES = %w[en de].freeze
  ROOT = Rails.root.join("app/views/comparisons")

  attr_reader :slug, :locale, :competitor, :competitor_url, :title, :description,
              :date, :table, :verdict_us, :verdict_them, :hreflang_alt, :body_markdown

  def self.all(locale: "en")
    return [] unless LOCALES.include?(locale)

    dir = ROOT.join(locale)
    return [] unless dir.directory?

    dir.glob("*.md").map { |path| from_path(path, locale: locale) }.compact.sort_by(&:competitor)
  end

  def self.find(slug, locale: "en")
    return nil unless LOCALES.include?(locale) && slug =~ BlogPost::SLUG_RE

    path = ROOT.join(locale, "#{slug}.md")
    return nil unless path.file?

    from_path(path, locale: locale)
  end

  def self.from_path(path, locale:)
    raw = path.read
    frontmatter, body = BlogPost.split_frontmatter(raw)
    return nil unless frontmatter

    slug = (frontmatter["slug"] || path.basename(".md").to_s).to_s
    return nil unless slug.match?(BlogPost::SLUG_RE)

    hreflang_alt = frontmatter["hreflang_alt"]
    return nil if hreflang_alt && !hreflang_alt.to_s.match?(BlogPost::SLUG_RE)

    new(
      slug: slug,
      locale: locale,
      competitor: frontmatter["competitor"],
      competitor_url: frontmatter["competitor_url"],
      title: frontmatter["title"],
      description: frontmatter["description"],
      date: frontmatter["date"].is_a?(Date) ? frontmatter["date"] : Date.parse(frontmatter["date"].to_s),
      table: frontmatter["table"] || [],
      verdict_us: frontmatter["verdict_us"],
      verdict_them: frontmatter["verdict_them"],
      hreflang_alt: hreflang_alt,
      body_markdown: body,
      mtime: path.mtime
    )
  rescue StandardError => e
    Rails.logger.warn("Comparison: failed to parse #{path}: #{e.class} #{e.message}")
    nil
  end

  def initialize(**attrs)
    attrs.each { |k, v| instance_variable_set("@#{k}", v) }
  end

  # Kramdown rendering cache keyed by file mtime. See BlogPost#body_html.
  def body_html
    key = "comparison/#{@locale}/#{@slug}/#{@mtime&.to_i || 0}/body_html"
    Rails.cache.fetch(key) do
      Kramdown::Document.new(
        @body_markdown.to_s,
        input: "GFM",
        hard_wrap: false,
        auto_ids: true,
        syntax_highlighter: nil
      ).to_html.html_safe
    end
  end

  def path
    @locale == "de" ? "/de/vs/#{@slug}" : "/vs/#{@slug}"
  end

  def hreflang_path
    return nil unless @hreflang_alt

    @locale == "de" ? "/vs/#{@hreflang_alt}" : "/de/vs/#{@hreflang_alt}"
  end
end
