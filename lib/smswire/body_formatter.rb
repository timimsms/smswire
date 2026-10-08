module Smswire
  module BodyFormatter
    module_function

    def call(text, mode = Smswire.config.body_whitespace)
      text = text.to_s
      case mode
      when :squish then text.squish
      when :preserve then text
      else text.gsub(/[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end
