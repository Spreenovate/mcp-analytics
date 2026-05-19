class SitemapsController < ApplicationController
  BASE_URL = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com").freeze

  def show
    @entries = build_entries
    response.set_header("Content-Type", "application/xml; charset=utf-8")
    response.set_header("Cache-Control", "public, max-age=3600")
    render layout: false
  end

  private

  def build_entries
    entries = []

    # Static pages.
    entries << { loc: "#{BASE_URL}/",        changefreq: "weekly",  priority: 1.0 }
    entries << { loc: "#{BASE_URL}/docs",    changefreq: "weekly",  priority: 0.8 }
    entries << { loc: "#{BASE_URL}/blog",    changefreq: "weekly",  priority: 0.7 }
    entries << { loc: "#{BASE_URL}/de/blog", changefreq: "weekly",  priority: 0.7 }
    entries << { loc: "#{BASE_URL}/vs",      changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{BASE_URL}/de/vs",   changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{BASE_URL}/mcp/tools", changefreq: "monthly", priority: 0.6 }
    entries << { loc: "#{BASE_URL}/ai-crawler-index", changefreq: "weekly", priority: 0.7 }

    # Blog posts (EN + DE).
    BlogPost::LOCALES.each do |locale|
      BlogPost.all(locale: locale).each do |post|
        entries << {
          loc: "#{BASE_URL}#{post.path}",
          lastmod: post.date.iso8601,
          changefreq: "monthly",
          priority: 0.7
        }
      end
    end

    # Comparison pages (EN + DE).
    Comparison::LOCALES.each do |locale|
      Comparison.all(locale: locale).each do |comp|
        entries << {
          loc: "#{BASE_URL}#{comp.path}",
          lastmod: comp.date.iso8601,
          changefreq: "monthly",
          priority: 0.7
        }
      end
    end

    # MCP tool pages.
    McpToolPage.all.each do |tool|
      entries << {
        loc: "#{BASE_URL}#{tool.path}",
        changefreq: "monthly",
        priority: 0.5
      }
    end

    entries
  end
end
