module Smswire
  # E.164 normalization.
  #
  # With phonelib loaded (or +phone_validator = :phonelib+) any region's
  # national format is supported. The built-in fallback accepts
  # international numbers written with + or 00, and national numbers for
  # North American Numbering Plan regions.
  module PhoneNumber
    E164 = /\A\+[1-9]\d{6,14}\z/
    NANP = /\A\+1[2-9]\d{2}[2-9]\d{6}\z/
    NANP_REGIONS = %w[US CA AG AI AS BB BM BS DM DO GD GU JM KN KY LC MP MS PR SX TC TT VC VG VI].freeze
    SEPARATORS = /[\s\-.()\/]/

    module_function

    # Returns the E.164 string, or nil when the input is not a valid number.
    def normalize(raw, region: Smswire.config.default_region)
      return nil if raw.blank?

      if use_phonelib?
        parsed = ::Phonelib.parse(raw.to_s, region)
        parsed.valid? ? parsed.e164 : nil
      else
        fallback(raw.to_s, region.to_s.upcase)
      end
    end

    def valid?(raw, **options)
      !normalize(raw, **options).nil?
    end

    def use_phonelib?
      case Smswire.config.phone_validator
      when :e164 then false
      when :phonelib
        require "phonelib" unless defined?(::Phonelib)
        true
      else
        defined?(::Phonelib) ? true : false
      end
    end

    def fallback(raw, region)
      compact = raw.strip.gsub(SEPARATORS, "")
      return nil unless compact.match?(/\A\+?\d+\z/)

      candidate =
        if compact.start_with?("+")
          compact
        elsif compact.start_with?("00")
          "+#{compact.delete_prefix("00")}"
        elsif NANP_REGIONS.include?(region)
          case compact.length
          when 10 then "+1#{compact}"
          when 11 then compact.start_with?("1") ? "+#{compact}" : nil
          end
        end

      return nil unless candidate&.match?(E164)
      return nil if candidate.start_with?("+1") && !candidate.match?(NANP)

      candidate
    end
  end
end
