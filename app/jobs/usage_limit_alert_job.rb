class UsageLimitAlertJob < ApplicationJob
  queue_as :default

  # Operator alert when a user crosses 150% of plan limit — potential
  # enterprise lead or abuse signal.
  OPERATOR_EMAIL = ENV.fetch("OPERATOR_EMAIL", "alex@mcp-analytics.com")
  THRESHOLD_RATIO = 1.5

  def perform
    current_month = Date.current.beginning_of_month

    totals = UsageCounter.where(month: current_month).group(:site_id).sum(:hit_count)
    return if totals.empty?

    sites_to_user = Site.where(site_id: totals.keys).pluck(:site_id, :user_id).to_h
    by_user = Hash.new(0)
    totals.each do |sid, n|
      uid = sites_to_user[sid]
      by_user[uid] += n if uid
    end

    User.where(id: by_user.keys).find_each do |user|
      hits = by_user[user.id]
      next if hits < user.plan_limit * THRESHOLD_RATIO

      # Only one alert per month/user — use cache as a tiny idempotency guard.
      flag = "usage_alert:#{user.id}:#{current_month}"
      next if Rails.cache.exist?(flag)

      Rails.cache.write(flag, "1", expires_in: 40.days, raw: true)

      OperatorMailer.usage_alert(user: user, hits: hits).deliver_later
    end
  end
end
