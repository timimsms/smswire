module Smswire
  class Configuration
    WHITESPACE_MODES = %i[strip squish preserve].freeze
    PHONE_VALIDATORS = %i[auto phonelib e164].freeze

    # Provider name used when a message or sender does not name one.
    # The Railtie defaults this to :log in development and :test in test.
    attr_accessor :default_provider

    # Per-provider options, e.g. { twilio: { account_sid: "...", auth_token: "..." } }.
    attr_accessor :providers

    # Named senders, e.g. { transactional: { number: "+1...", provider: :twilio } }.
    attr_accessor :senders

    # Callable that turns a recipient object into a phone number string.
    # When nil, objects responding to +phone_number+ are used.
    attr_accessor :recipient_resolver

    # ISO 3166 region used to parse numbers written in national format.
    attr_accessor :default_region

    # :auto uses phonelib when it is loaded, :phonelib requires it, and
    # :e164 uses the built-in validator (E.164 plus NANP national formats).
    attr_reader :phone_validator

    attr_accessor :default_category

    # Total attempts for transient errors in Smswire::DeliveryJob,
    # counting the first.
    attr_accessor :retry_attempts

    attr_accessor :deliver_later_queue

    # How rendered and literal bodies are cleaned before sending.
    # :strip removes trailing spaces on each line, collapses three or more
    # newlines to two, and strips the ends. :squish collapses all
    # whitespace to single spaces. :preserve leaves the body untouched.
    attr_reader :body_whitespace

    attr_accessor :interceptors, :observers, :logger

    # Record every send in smswire_deliveries. Requires the engine migrations.
    attr_accessor :persist_deliveries

    # Identical messages (same messenger, action, recipient, and body, or the
    # same explicit idempotency_key) inside this window are refused as
    # :duplicate. nil disables deduplication.
    attr_accessor :dedupe_window

    # Public base URL where Smswire::Engine is mounted, e.g.
    # "https://app.example.com/smswire". When set, providers that support
    # status callbacks are told to post to "<callbacks_url>/status/<provider>".
    attr_accessor :callbacks_url

    attr_accessor :verify_callback_signatures

    # Store message bodies on deliveries. Overridden per category with
    # categories: { otp: { store_body: false } }.
    attr_accessor :store_bodies

    # Per-category settings. Phase 2 honors :store_body.
    attr_accessor :categories

    def initialize
      @default_provider = nil
      @providers = {}
      @senders = {}
      @recipient_resolver = nil
      @default_region = "US"
      @phone_validator = :auto
      @default_category = :transactional
      @retry_attempts = 5
      @deliver_later_queue = :default
      @body_whitespace = :strip
      @interceptors = []
      @observers = []
      @logger = nil
      @persist_deliveries = true
      @dedupe_window = 10.minutes
      @callbacks_url = nil
      @verify_callback_signatures = true
      @store_bodies = true
      @categories = {otp: {store_body: false}}
    end

    def phone_validator=(value)
      value = value.to_sym
      unless PHONE_VALIDATORS.include?(value)
        raise ConfigurationError, "phone_validator must be one of #{PHONE_VALIDATORS.join(", ")}"
      end
      @phone_validator = value
    end

    def body_whitespace=(value)
      value = value.to_sym
      unless WHITESPACE_MODES.include?(value)
        raise ConfigurationError, "body_whitespace must be one of #{WHITESPACE_MODES.join(", ")}"
      end
      @body_whitespace = value
    end

    def category_options(category)
      (categories[category.to_s.to_sym] || categories[category.to_s] || {}).to_h.symbolize_keys
    end

    def store_body?(category)
      setting = category_options(category)[:store_body]
      setting.nil? ? store_bodies : setting
    end

    def provider_options(name)
      (providers[name.to_sym] || providers[name.to_s] || {}).to_h.symbolize_keys
    end
  end
end
