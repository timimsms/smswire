module Smswire
  # Encoding and segment calculation for SMS bodies.
  #
  # A body that fits the GSM 03.38 alphabet is sent as GSM-7: 160 units in
  # one segment, 153 per segment when concatenated. Extension-table
  # characters cost two units. Anything else is sent as UCS-2: 70 units in
  # one segment, 67 per segment, where characters outside the Basic
  # Multilingual Plane (most emoji) cost two units. Characters are never
  # split across segments, so packing is greedy rather than a division.
  module Segments
    GSM_BASIC = Set.new(
      "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?" \
      "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà".chars
    ).freeze
    GSM_EXTENDED = Set.new("\f^{}\\[~]|€".chars).freeze

    LIMITS = {
      gsm7: {single: 160, multi: 153},
      ucs2: {single: 70, multi: 67}
    }.freeze

    Analysis = Data.define(:encoding, :units, :segments) do
      def gsm7? = encoding == :gsm7

      def ucs2? = encoding == :ucs2

      def encoding_label = gsm7? ? "GSM-7" : "UCS-2"

      # Units left before the message needs another segment.
      def remaining
        limits = LIMITS.fetch(encoding)
        capacity = (segments <= 1) ? limits[:single] : segments * limits[:multi]
        [capacity - units, 0].max
      end
    end

    module_function

    def analyze(text)
      chars = text.to_s.chars
      encoding = gsm7?(chars) ? :gsm7 : :ucs2
      costs = chars.map { |char| cost(char, encoding) }
      units = costs.sum
      Analysis.new(encoding:, units:, segments: count(costs, units, LIMITS.fetch(encoding)))
    end

    # Characters that force UCS-2 encoding, in order of appearance.
    def non_gsm_characters(text)
      text.to_s.chars.reject { |char| GSM_BASIC.include?(char) || GSM_EXTENDED.include?(char) }.uniq
    end

    def gsm7?(chars)
      chars.all? { |char| GSM_BASIC.include?(char) || GSM_EXTENDED.include?(char) }
    end

    def cost(char, encoding)
      if encoding == :gsm7
        GSM_EXTENDED.include?(char) ? 2 : 1
      else
        (char.ord > 0xFFFF) ? 2 : 1
      end
    end

    def count(costs, units, limits)
      return 0 if units.zero?
      return 1 if units <= limits[:single]

      segments = 1
      used = 0
      costs.each do |cost|
        if used + cost > limits[:multi]
          segments += 1
          used = cost
        else
          used += cost
        end
      end
      segments
    end
  end
end
