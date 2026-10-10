require "securerandom"

module Smswire
  module Providers
    # Writes messages, including the body, to Smswire.logger instead of
    # sending them. The default provider in development.
    class Log < Base
      def verify_credentials! = true

      def deliver(message)
        analysis = message.analysis
        sender = message.from || message.messaging_service || "(none)"
        lines = ["[Smswire] SMS to #{message.to} from #{sender} via #{message.messenger}##{message.action}",
          "[Smswire] #{analysis.segments} segment(s), #{analysis.encoding_label}, #{analysis.units} units"]
        lines << "[Smswire] media: #{message.media_urls.join(", ")}" if message.media_urls.any?
        lines << message.body.to_s
        Smswire.logger.info(lines.join("\n"))

        receipt(provider_id: "log-#{SecureRandom.hex(8)}", status: :accepted, segments: analysis.segments)
      end
    end
  end
end
