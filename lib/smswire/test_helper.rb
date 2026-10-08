require "active_job/test_helper"

module Smswire
  # Minitest assertions for messengers.
  #
  #   class OrderTest < ActiveSupport::TestCase
  #     include Smswire::TestHelper
  #
  #     test "ships" do
  #       assert_sms_delivered(to: "+15551234567", messenger: OrderMessenger, action: :shipped) do
  #         Order.ship!(order)
  #       end
  #     end
  #   end
  #
  # Deliveries are cleared before each test. With a block, enqueued
  # Smswire::DeliveryJob jobs are performed so deliver_later is covered.
  module TestHelper
    include ActiveJob::TestHelper

    def before_setup
      Smswire::Testing.clear!
      super
    end

    def sms_deliveries
      Smswire::Testing.deliveries
    end

    def assert_sms_delivered(count = nil, **filters, &block)
      delivered =
        if block
          before = Smswire::Testing.deliveries.size
          perform_enqueued_jobs(only: Smswire::DeliveryJob, &block)
          Smswire::Testing.deliveries.drop(before)
        else
          Smswire::Testing.deliveries
        end
      matching = Smswire::Testing.match_deliveries(delivered, **filters)
      described = Smswire::Testing.describe_filters(filters)

      if count
        assert_equal count, matching.size,
          "Expected #{count} SMS#{described}, got #{matching.size} (#{delivered.size} delivered in total)"
      else
        assert matching.any?, "Expected an SMS#{described}, but none was delivered (#{delivered.size} in total)"
      end
      matching
    end

    def assert_no_sms_delivered(**filters, &block)
      assert_sms_delivered(0, **filters, &block)
    end

    def assert_enqueued_sms(messenger = nil, action = nil, count: nil, params: nil, args: nil, kwargs: nil, &block)
      jobs =
        if block
          before = enqueued_jobs.size
          block.call
          enqueued_jobs.drop(before)
        else
          enqueued_jobs
        end
      entries = Smswire::Testing.enqueued(jobs)
      matching = Smswire::Testing.match_enqueued(entries, messenger:, action:, params:, args:, kwargs:)
      label = [messenger, action].compact.join("#")
      label = label.empty? ? "an SMS" : label

      if count
        assert_equal count, matching.size, "Expected #{count} enqueued #{label}, got #{matching.size}"
      else
        assert matching.any?, "Expected #{label} to be enqueued, but it was not (#{entries.size} SMS enqueued)"
      end
      matching
    end

    def assert_no_enqueued_sms(messenger = nil, action = nil, **filters, &block)
      assert_enqueued_sms(messenger, action, count: 0, **filters, &block)
    end
  end
end
