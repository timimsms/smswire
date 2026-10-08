module Smswire
  # Runs a message through normalize, validate, claim, intercept, send,
  # record, and observe.
  #
  # Returns a Smswire::Result. Permanent provider errors become a :failed
  # result. Transient errors and configuration errors propagate so the
  # caller (or Smswire::DeliveryJob) can retry or fail loudly. When
  # persistence is enabled, each claimed message has a Smswire::Delivery row
  # that a retry reuses, so a message is never recorded twice.
  class Pipeline
    def self.call(message)
      new(message).call
    end

    attr_reader :message

    def initialize(message)
      @message = message
    end

    def call
      normalized = PhoneNumber.normalize(message.to)
      return reject(:rejected_invalid_number) unless normalized
      message.to = normalized

      return reject(:rejected_empty_body) if message.body.blank? && message.media_urls.empty?

      rule = Smswire.config.category_options(message.category)
      if (status = consent_rejection(rule))
        return reject(status)
      end
      if (resume_at = QuietHours.resume_at(rule[:quiet_hours], time_zone: QuietHours.time_zone_for(message.recipient)))
        return defer(:deferred_quiet_hours, resume_at)
      end
      if rule[:rate_limit] && (resume_at = RateLimit.resume_at(message, rule[:rate_limit]))
        return reject(:rejected_rate_limited) if rule[:rate_limit][:exceed]&.to_sym == :reject
        return defer(:deferred_rate_limited, resume_at)
      end

      provider = Providers.resolve(message.provider)
      message.lock_idempotency_key!

      delivery = nil
      if Smswire.config.persist_deliveries
        delivery = Delivery.claim_for(message, provider: provider.name)
        return reject(:duplicate) unless delivery
        message.status_callback_url ||= Callbacks.status_url(provider.name, delivery) if provider.capabilities.include?(:status_callbacks)
      end

      run_interceptors
      unless message.perform_deliveries?
        delivery&.record_suppression!(message)
        return finish(Result.new(status: :suppressed_by_interceptor, message:, delivery:))
      end

      deliver(provider, delivery)
    end

    private

    def deliver(provider, delivery)
      payload = message.to_log_h.merge(provider: provider.name, delivery_id: delivery&.id)
      receipt = ActiveSupport::Notifications.instrument("deliver.smswire", payload) do
        provider.deliver(message).tap do |r|
          payload[:provider_id] = r.provider_id
          payload[:status] = r.status
        end
      end
      delivery&.record_receipt!(receipt, message)
      status = (receipt.status == :failed) ? :failed : :accepted
      finish(Result.new(status:, message:, receipt:, delivery:))
    rescue PermanentError => error
      delivery&.record_failure!(error, message)
      if error.opted_out? && Smswire.config.enforce_consent
        Consent.opt_out!(message.to, scope: message.consent_scope, source: :carrier)
      end
      finish(Result.new(status: :failed, message:, error:, delivery:))
    rescue TransientError => error
      delivery&.release!(error)
      raise
    end

    def consent_rejection(rule)
      return nil if rule[:consent] == :none || !Smswire.config.enforce_consent

      status = Consent.status_for(message.to, scope: message.consent_scope)
      return :rejected_opted_out if status == "opted_out"
      :rejected_no_consent if rule[:consent] == :require_opted_in && status != "opted_in"
    end

    def defer(status, resume_at)
      ActiveSupport::Notifications.instrument("reject.smswire", message.to_log_h.merge(reason: status, resume_at:))
      finish(Result.new(status:, message:, resume_at:))
    end

    def reject(status)
      ActiveSupport::Notifications.instrument("reject.smswire", message.to_log_h.merge(reason: status))
      finish(Result.new(status:, message:))
    end

    def finish(result)
      Smswire.config.observers.each { |observer| resolve(observer).delivered_sms(result) }
      result
    end

    def run_interceptors
      Smswire.config.interceptors.each { |interceptor| resolve(interceptor).delivering_sms(message) }
    end

    def resolve(hook)
      hook.is_a?(String) ? hook.constantize : hook
    end
  end
end
