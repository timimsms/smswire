module Smswire
  # Shared matching logic for Smswire::TestHelper and the RSpec matchers.
  module Testing
    DELIVERY_FILTERS = %i[to from body messenger action category provider].freeze

    module_function

    def deliveries
      Providers::Test.deliveries
    end

    def clear!
      Providers::Test.clear!
    end

    def match_deliveries(messages, **filters)
      unknown = filters.keys - DELIVERY_FILTERS
      raise ArgumentError, "Unknown filter(s): #{unknown.join(", ")}" if unknown.any?

      messages.select do |message|
        filters.all? do |key, expected|
          actual = message.public_send(key)
          case key
          when :to then expected_phone?(actual, expected)
          when :messenger then matches?(actual, expected.is_a?(Class) ? expected.name : expected)
          else matches?(actual, expected)
          end
        end
      end
    end

    # Enqueued Smswire::DeliveryJob entries from an ActiveJob test adapter,
    # deserialized into hashes with :messenger, :action, :params, :args, :kwargs.
    def enqueued(jobs)
      jobs.filter_map do |job|
        job_class = job[:job] || job["job_class"]
        next unless job_class.to_s == DeliveryJob.name

        messenger, action, params, args, kwargs = ActiveJob::Arguments.deserialize(job[:args] || job["arguments"])
        {messenger:, action:, params:, args:, kwargs:, queue: job[:queue], at: job[:at]}
      end
    end

    def match_enqueued(entries, messenger: nil, action: nil, params: nil, args: nil, kwargs: nil)
      entries.select do |entry|
        (messenger.nil? || entry[:messenger] == (messenger.is_a?(Class) ? messenger.name : messenger.to_s)) &&
          (action.nil? || entry[:action] == action.to_s) &&
          (params.nil? || entry[:params] == params) &&
          (args.nil? || entry[:args] == args) &&
          (kwargs.nil? || entry[:kwargs] == kwargs)
      end
    end

    def describe_filters(filters)
      filters.empty? ? "" : " matching #{filters.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}"
    end

    def matches?(actual, expected)
      case expected
      when Regexp then expected.match?(actual.to_s)
      when Symbol then actual.to_s == expected.to_s
      else actual == expected
      end
    end

    def expected_phone?(actual, expected)
      return expected.match?(actual.to_s) if expected.is_a?(Regexp)

      actual == expected || actual == PhoneNumber.normalize(expected)
    end
  end
end
