module Smswire
  # Quiet-hour windows given as "HH:MM".."HH:MM" in the recipient's local
  # time. A window whose start is after its end wraps past midnight. The
  # start is inclusive and the end exclusive.
  module QuietHours
    FORMAT = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

    module_function

    # Returns when sending may resume, or nil when +now+ is outside the window.
    def resume_at(window, time_zone:, now: Time.current)
      return nil if window.blank?

      start_minute, end_minute = parse(window)
      local = now.in_time_zone(time_zone)
      minute = (local.hour * 60) + local.min
      quiet =
        if start_minute < end_minute
          minute >= start_minute && minute < end_minute
        else
          minute >= start_minute || minute < end_minute
        end
      return nil unless quiet

      resume = local.change(hour: end_minute / 60, min: end_minute % 60)
      (resume > local) ? resume : resume.advance(days: 1)
    end

    def parse(window)
      unless window.is_a?(Range)
        raise ConfigurationError, "quiet_hours must be a Range like \"21:00\"..\"08:00\", got #{window.inspect}"
      end
      [window.begin, window.end].map do |value|
        match = FORMAT.match(value.to_s) or raise ConfigurationError, "Invalid quiet_hours time #{value.inspect}"
        (match[1].to_i * 60) + match[2].to_i
      end
    end

    def time_zone_for(recipient)
      zone = recipient&.time_zone
      zone = ActiveSupport::TimeZone[zone] if zone.is_a?(String)
      zone || Smswire.config.time_zone
    end
  end
end
