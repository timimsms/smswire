module Smswire
  # Runs a message through normalize, validate, intercept, send, and observe.
  #
  # Returns a Smswire::Result. Permanent provider errors become a :failed
  # result. Transient errors and configuration errors propagate so the
  # caller (or Smswire::DeliveryJob) can retry or fail loudly.
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

      run_interceptors
      return finish(Result.new(status: :suppressed_by_interceptor, message:)) unless message.perform_deliveries?

      deliver
    end

    private

    def deliver
      provider = Providers.resolve(message.provider)
      payload = message.to_log_h.merge(provider: provider.name)
      receipt = ActiveSupport::Notifications.instrument("deliver.smswire", payload) do
        provider.deliver(message).tap do |r|
          payload[:provider_id] = r.provider_id
          payload[:status] = r.status
        end
      end
      status = (receipt.status == :failed) ? :failed : :accepted
      finish(Result.new(status:, message:, receipt:))
    rescue PermanentError => error
      finish(Result.new(status: :failed, message:, error:))
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
