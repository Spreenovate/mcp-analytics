class SitemapsController < ApplicationController
  def show
    @entries = Rails.cache.fetch("sitemap.xml/entries", expires_in: 1.hour) { build_entries }
    response.set_header("Content-Type", "application/xml; charset=utf-8")
    response.set_header("Cache-Control", "public, max-age=3600")
    render layout: false
  end

  private

  def base_url
    ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
  end

  def build_entries
    base = base_url
    entries = []

    # Static pages.
    entries << { loc: "#{base}/",        changefreq: "weekly",  priority: 1.0 }
    entries << { loc: "#{base}/docs",    changefreq: "weekly",  priority: 0.8 }
    entries << { loc: "#{base}/blog",    changefreq: "weekly",  priority: 0.7 }
    entries << { loc: "#{base}/de/blog", changefreq: "weekly",  priority: 0.7 }
    entries << { loc: "#{base}/vs",      changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{base}/de/vs",   changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{base}/mcp/tools", changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{base}/ai-crawler-index", changefreq: "weekly", priority: 0.7 }

    # Blog posts (EN + DE).
    BlogPost::LOCALES.each do |locale|
      BlogPost.all(locale: locale).each do |post|
        entries << {
          loc: "#{base}#{post.path}",
          lastmod: post.lastmod_date.iso8601,
          changefreq: "monthly",
          priority: 0.7
        }
      end
    end

    # Comparison pages (EN + DE).
    Comparison::LOCALES.each do |locale|
      Comparison.all(locale: locale).each do |comp|
        entries << {
          loc: "#{base}#{comp.path}",
          lastmod: comp.lastmod_date.iso8601,
          changefreq: "monthly",
          priority: 0.7
        }
      end
    end

    # MCP tool pages.
    McpToolPage.all.each do |tool|
      entries << {
        loc: "#{base}#{tool.path}",
        changefreq: "monthly",
        priority: 0.5
      }
    end

    entries
  end
end
