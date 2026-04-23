module Analytics
  # Period resolves the user-facing period keywords into concrete
  # [from, to] UTC time ranges. Accepts keywords or explicit ranges
  # like "YYYY-MM-DD..YYYY-MM-DD".
  class Period
    KEYWORDS = %w[today yesterday last_7_days last_30_days last_90_days last_12_months].freeze

    attr_reader :from, :to, :label

    def self.parse(spec)
      new(spec).resolve
    end

    def initialize(spec)
      @spec = (spec || "last_7_days").to_s
    end

    def resolve
      now = Time.now.utc
      today = now.to_date

      case @spec
      when "today"
        @from = today.beginning_of_day
        @to   = now
      when "yesterday"
        @from = (today - 1).beginning_of_day
        @to   = (today - 1).end_of_day
      when "last_7_days"
        @from = (today - 6).beginning_of_day
        @to   = now
      when "last_30_days"
        @from = (today - 29).beginning_of_day
        @to   = now
      when "last_90_days"
        @from = (today - 89).beginning_of_day
        @to   = now
      when "last_12_months"
        @from = (today << 12).beginning_of_day
        @to   = now
      when /\A(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})\z/
        @from = Date.parse(Regexp.last_match(1)).beginning_of_day
        @to   = Date.parse(Regexp.last_match(2)).end_of_day
      else
        raise ArgumentError, "unknown period: #{@spec.inspect}"
      end

      @label = @spec
      self
    end

    def from_sql
      from.utc.strftime("%Y-%m-%d %H:%M:%S")
    end

    def to_sql
      to.utc.strftime("%Y-%m-%d %H:%M:%S")
    end

    def duration_seconds
      (to - from).to_i
    end

    def previous
      Period.new("#{(from - duration_seconds).to_date}..#{(to - duration_seconds).to_date}").resolve
    end
  end
end
