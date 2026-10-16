module Smswire
  # Per-recipient, per-category sliding-window limits counted from
  # smswire_deliveries. Failed and suppressed deliveries do not count.
  # Concurrent sends can briefly exceed the limit by the number of workers.
  module RateLimit
    COUNTED = %w[pending queued accepted sent delivered undelivered read].freeze

    module_function

    # Returns when the next send fits the window, or nil when it fits now.
    def resume_at(message, rule, now: Time.current)
      max = rule.fetch(:max)
      per = rule.fetch(:per)
      unless Smswire.config.persist_deliveries
        raise ConfigurationError, "Rate limits require persist_deliveries"
      end

      recent = Delivery.where(to_number: message.to, category: message.category.to_s, status: COUNTED)
        .where(Delivery.arel_table[:created_at].gt(now - per))
      count = recent.count
      return nil if count < max

      oldest = recent.order(:created_at).offset(count - max).pick(:created_at)
      oldest + per
    end
  end
end
