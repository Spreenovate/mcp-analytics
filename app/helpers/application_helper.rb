module ApplicationHelper
  # Embed a value inside a <script type="application/ld+json"> block.
  # Ruby's to_json does NOT escape "</script>", so a string value
  # containing that sequence would break out of the script context.
  # Escape the forward slash in "</" to "<\/" — JSON parsers handle
  # the escape, HTML doesn't see the closing tag. Standard practice
  # for safely embedding JSON in HTML script tags.
  def json_ld(value)
    value.to_json.gsub("</", "<\\/").html_safe
  end
end
