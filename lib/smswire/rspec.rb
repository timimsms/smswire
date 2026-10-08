require "smswire"
require "rspec/expectations"

module Smswire
  # RSpec matchers. Load with +require "smswire/rspec"+.
  #
  #   expect { order.ship! }.to deliver_sms(to: "+15551234567", body: /shipped/)
  #   expect { order.ship! }.to deliver_sms.exactly(2).times
  #   expect { order.ship! }.to have_enqueued_sms(OrderMessenger, :shipped)
  #
  # +deliver_sms+ counts deliveries made during the block. Wrap the block
  # in +perform_enqueued_jobs+ to include deliver_later.
  module RSpec
    module Matchers
      def deliver_sms(**filters)
        DeliverSms.new(filters)
      end

      def have_enqueued_sms(messenger = nil, action = nil, **filters)
        HaveEnqueuedSms.new(messenger, action, filters)
      end

      module Counting
        def exactly(count)
          @expected_count = count
          self
        end

        def once = exactly(1)

        def twice = exactly(2)

        def times = self

        def supports_block_expectations? = true

        private

        def count_matches?(actual)
          @expected_count ? actual == @expected_count : actual.positive?
        end

        def expectation
          @expected_count ? "exactly #{@expected_count}" : "at least one"
        end
      end

      class DeliverSms
        include ::RSpec::Matchers::Composable
        include Counting

        def initialize(filters)
          @filters = filters
        end

        def matches?(block)
          before = Smswire::Testing.deliveries.size
          block.call
          @delivered = Smswire::Testing.deliveries.drop(before)
          @matching = Smswire::Testing.match_deliveries(@delivered, **@filters)
          count_matches?(@matching.size)
        end

        def failure_message
          "expected #{expectation} SMS#{described} to be delivered, got #{@matching.size} " \
            "(#{@delivered.size} delivered in total)"
        end

        def failure_message_when_negated
          "expected no SMS#{described} to be delivered, got #{@matching.size}"
        end

        def description
          "deliver #{expectation} SMS#{described}"
        end

        private

        def described = Smswire::Testing.describe_filters(@filters)
      end

      class HaveEnqueuedSms
        include ::RSpec::Matchers::Composable
        include Counting

        def initialize(messenger, action, filters)
          @messenger = messenger
          @action = action
          @filters = filters
        end

        def matches?(block)
          adapter = ActiveJob::Base.queue_adapter
          unless adapter.respond_to?(:enqueued_jobs)
            raise ArgumentError, "have_enqueued_sms requires the ActiveJob :test adapter"
          end

          before = adapter.enqueued_jobs.size
          block.call
          entries = Smswire::Testing.enqueued(adapter.enqueued_jobs.drop(before))
          @matching = Smswire::Testing.match_enqueued(entries, messenger: @messenger, action: @action, **@filters)
          count_matches?(@matching.size)
        end

        def failure_message
          "expected #{expectation} #{label} to be enqueued, got #{@matching.size}"
        end

        def failure_message_when_negated
          "expected no #{label} to be enqueued, got #{@matching.size}"
        end

        def description
          "enqueue #{expectation} #{label}"
        end

        private

        def label
          name = [@messenger, @action].compact.join("#")
          name.empty? ? "SMS" : name
        end
      end
    end
  end
end

if defined?(::RSpec::Core) && ::RSpec.respond_to?(:configure)
  ::RSpec.configure do |config|
    config.include Smswire::RSpec::Matchers
    config.before { Smswire::Testing.clear! }
  end
end
