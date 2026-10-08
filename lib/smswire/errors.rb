module Smswire
  class Error < StandardError; end

  # Raised for missing or invalid configuration: no provider, unknown sender,
  # missing credentials. Never retried.
  class ConfigurationError < Error; end

  # Raised when +text to:+ is given something that cannot produce a phone
  # number. Raised while building the message so it surfaces in tests.
  class UnresolvableRecipient < Error; end

  # Raised when a provider callback fails signature verification.
  class SignatureError < Error; end

  # Base class for errors raised by provider adapters.
  class DeliveryError < Error
    attr_reader :provider, :provider_code, :http_status, :raw

    def initialize(message = nil, provider: nil, provider_code: nil, http_status: nil, raw: nil)
      super(message)
      @provider = provider
      @provider_code = provider_code
      @http_status = http_status
      @raw = raw
    end
  end

  # Network failures, timeouts, and provider 5xx responses. Retried by
  # Smswire::DeliveryJob and re-raised from +deliver_now+.
  class TransientError < DeliveryError; end

  # Provider rate limiting. Retried after +retry_after+ seconds when known.
  class ThrottledError < TransientError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **options)
      super(message, **options)
      @retry_after = retry_after
    end
  end

  # The provider refused the message and retrying will not help. The
  # pipeline turns this into a +:failed+ result instead of raising.
  #
  # +reason+ is one of :invalid_number, :opted_out, :unroutable,
  # :authentication, or :rejected.
  class PermanentError < DeliveryError
    attr_reader :reason

    def initialize(message = nil, reason: :rejected, **options)
      super(message, **options)
      @reason = reason
    end

    def opted_out?
      reason == :opted_out
    end
  end
end
