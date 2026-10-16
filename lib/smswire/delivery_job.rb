module Smswire
  # Delivers a messenger action in the background. Transient errors are
  # retried with polynomial backoff up to Smswire.config.retry_attempts
  # total attempts. Throttled errors wait for the provider's Retry-After.
  # Permanent errors are recorded as :failed results and not retried.
  class DeliveryJob < ActiveJob::Base
    queue_as { Smswire.config.deliver_later_queue }

    rescue_from TransientError do |error|
      raise error if executions >= Smswire.config.retry_attempts

      retry_job(wait: retry_wait(error))
    end

    def perform(messenger_name, action, params, args, kwargs)
      MessageDelivery.new(messenger_name.constantize, action, args:, kwargs:, params:).deliver_now
    end

    private

    def retry_wait(error)
      if error.is_a?(ThrottledError) && error.retry_after
        error.retry_after.seconds
      else
        ((executions**4) + 2).seconds
      end
    end
  end
end
