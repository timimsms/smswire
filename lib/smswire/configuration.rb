module Smswire
  class Configuration
    WHITESPACE_MODES = %i[strip squish preserve].freeze
    CONSENT_RULES = %i[allow_unless_opted_out require_opted_in none].freeze

    # Shipped category rules. Settings in +categories+ are merged over these
    # per key, so overriding one category leaves the others intact.
    # Marketing quiet hours follow the US federal TCPA window (8am to 9pm
    # recipient time); some states are stricter.
    DEFAULT_CATEGORIES = {
      otp: {consent: :allow_unless_opted_out, store_body: false},
      transactional: {consent: :allow_unless_opted_out},
      marketing: {consent: :require_opted_in, quiet_hours: "21:00".."08:00"},
      compliance: {consent: :none}
    }.freeze

    DEFAULT_KEYWORDS = {
      opt_out: %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT OPTOUT REVOKE],
      opt_in: %w[START YES UNSTOP],
      help: %w[HELP INFO]
    }.freeze

    DEFAULT_KEYWORD_REPLIES = {
      opt_out: "You have been unsubscribed from %{program} messages and will not receive any more. Reply START to resubscribe.",
      opt_in: "You are subscribed to %{program} messages again. Reply STOP to unsubscribe, HELP for help.",
      help: "%{program}: Reply STOP to unsubscribe. Msg & data rates may apply."
    }.freeze
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

    # Per-category settings merged over DEFAULT_CATEGORIES:
    #   consent:     :allow_unless_opted_out, :require_opted_in, or :none
    #   quiet_hours: "21:00".."08:00" in the recipient's time zone, or nil
    #   rate_limit:  { max: 3, per: 1.day, exceed: :defer }  (or :reject)
    #   store_body:  overrides store_bodies
    attr_accessor :categories

    # Check consent before sending and record carrier opt-outs. Turn off
    # only when another system, such as Twilio Advanced Opt-Out, owns consent.
    attr_accessor :enforce_consent

    # Time zone for quiet hours when the recipient has none. Defaults to
    # Time.zone.
    attr_accessor :default_time_zone

    # Inbound keyword sets: { opt_out: [...], opt_in: [...], help: [...] }.
    attr_accessor :keywords

    # Auto-reply bodies per keyword kind; %{program} is replaced by
    # program_name. Set a kind to nil to send no reply.
    attr_accessor :keyword_replies

    attr_accessor :program_name

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
      @categories = {}
      @enforce_consent = true
      @default_time_zone = nil
      @keywords = DEFAULT_KEYWORDS.transform_values(&:dup)
      @keyword_replies = DEFAULT_KEYWORD_REPLIES.dup
      @program_name = nil
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
      key = category.to_s.to_sym
      custom = (categories[key] || categories[category.to_s] || {}).to_h.symbolize_keys
      options = DEFAULT_CATEGORIES.fetch(key, {}).merge(custom)
      consent = options.fetch(:consent, :allow_unless_opted_out).to_sym
      unless CONSENT_RULES.include?(consent)
        raise ConfigurationError, "Unknown consent rule #{consent.inspect} for category #{key}"
      end
      options.merge(consent:)
    end

    def time_zone
      zone = default_time_zone || Time.zone || "UTC"
      ActiveSupport::TimeZone[zone] || raise(ConfigurationError, "Unknown time zone #{zone.inspect}")
    end

    def consent_scopes
      scopes = senders.values.filter_map { |options| options.to_h.symbolize_keys[:consent_scope]&.to_s }
      (["default"] + scopes).uniq
    end

    def keyword_reply(kind)
      template = keyword_replies[kind.to_sym] or return nil
      format(template, program: program_name || default_program_name)
    end

    def store_body?(category)
      setting = category_options(category)[:store_body]
      setting.nil? ? store_bodies : setting
    end

    def default_program_name
      if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
        ::Rails.application.class.module_parent_name.titleize
      else
        "our"
      end
    end

    def provider_options(name)
      (providers[name.to_sym] || providers[name.to_s] || {}).to_h.symbolize_keys
    end
  end
end
