require "securerandom"

module Smswire
  module Providers
    # Records messages in memory. The default provider in the test
    # environment.
    #
    #   Smswire::Providers::Test.deliveries  # => [#<Smswire::Message ...>]
    #   Smswire::Providers::Test.fail_next(Smswire::PermanentError.new("nope", reason: :opted_out))
    class Test < Base
      @deliveries = []
      @failures = []
      @mutex = Mutex.new

      class << self
        attr_reader :mutex

        def deliveries
          mutex.synchronize { @deliveries.dup }
        end

        def record(message)
          mutex.synchronize { @deliveries << message }
        end

        # Raise +error+ on the next delivery instead of recording it.
        def fail_next(error)
          mutex.synchronize { @failures << error }
        end

        def next_failure
          mutex.synchronize { @failures.shift }
        end

        def clear!
          mutex.synchronize do
            @deliveries.clear
            @failures.clear
          end
        end
      end

      def verify_credentials! = true

      def deliver(message)
        if (error = self.class.next_failure)
          raise error
        end

        self.class.record(message)
        receipt(provider_id: "SMtest#{SecureRandom.hex(12)}", status: :accepted, segments: message.segments)
      end

      def capabilities
        Set[:mms]
      end
    end
  end
end
