module Smswire
  module Interceptors
    # Staging safety: only listed numbers receive messages.
    #
    #   Smswire.register_interceptor(
    #     Smswire::Interceptors::Allowlist.new(numbers: ENV.fetch("SMS_ALLOWLIST", "").split(","))
    #   )
    #
    # Other recipients are suppressed, or with +redirect_to:+ rerouted to
    # that number with the original recipient prefixed to the body.
    class Allowlist
      attr_reader :numbers, :redirect_to

      def initialize(numbers:, redirect_to: nil)
        @numbers = Array(numbers).filter_map { |number| PhoneNumber.normalize(number.to_s.strip) }.to_set
        @redirect_to = redirect_to && (PhoneNumber.normalize(redirect_to) or
          raise ConfigurationError, "Invalid redirect_to number #{redirect_to.inspect}")
      end

      def allowed?(number)
        numbers.include?(number)
      end

      def delivering_sms(message)
        return if allowed?(message.to)

        if redirect_to
          message.body = "[to #{message.to}] #{message.body}"
          message.to = redirect_to
        else
          message.cancel!
        end
      end
    end
  end
end
