module Smswire
  # Logs deliveries, rejections, and status updates. Phone numbers are
  # masked and bodies are never logged.
  class LogSubscriber < ActiveSupport::LogSubscriber
    def deliver(event)
      payload = event.payload
      route = "#{payload[:messenger]}##{payload[:action]} to #{mask(payload[:to])} via #{payload[:provider]}"
      if (error = payload[:exception_object])
        warn { "SMS #{route} raised #{error.class}: #{error.message} (#{event.duration.round(1)}ms)" }
      else
        info do
          "SMS #{route}: #{payload[:status]} #{payload[:provider_id]} " \
            "(#{payload[:segments]} segment(s), #{event.duration.round(1)}ms)"
        end
      end
    end

    def reject(event)
      payload = event.payload
      info { "SMS #{payload[:messenger]}##{payload[:action]} to #{mask(payload[:to])} not sent: #{payload[:reason]}" }
    end

    def status_update(event)
      payload = event.payload
      if payload[:delivery_id]
        info do
          "SMS status #{payload[:provider]} #{payload[:provider_id]}: #{payload[:status]} " \
            "(delivery #{payload[:delivery_id]} now #{payload[:delivery_status]})"
        end
      else
        warn { "SMS status #{payload[:provider]} #{payload[:provider_id]}: #{payload[:status]} for unknown delivery" }
      end
    end

    def logger
      Smswire.logger
    end

    private

    def mask(number)
      number = number.to_s
      return number if number.length < 8

      "#{number[0, 2]}#{"*" * (number.length - 6)}#{number[-4..]}"
    end
  end
end
