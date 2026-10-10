require "abstract_controller"
require "action_view"

module Smswire
  # Base class for messengers, modeled on ActionMailer::Base.
  #
  #   class OrderMessenger < Smswire::Base
  #     default from: :transactional
  #
  #     def shipped(user)
  #       @order = params[:order]
  #       text to: user   # renders app/views/order_messenger/shipped.text.erb
  #     end
  #   end
  #
  #   OrderMessenger.with(order:).shipped(user).deliver_later
  class Base < AbstractController::Base
    include AbstractController::Rendering
    include AbstractController::Logger
    include AbstractController::Helpers
    include AbstractController::Translation
    include AbstractController::Callbacks
    include ActionView::Layouts

    abstract!

    TEXT_OPTIONS = %i[category provider messaging_service media_urls metadata idempotency_key validity_period consent_scope].freeze
    DEFAULT_KEYS = (%i[from] + TEXT_OPTIONS - %i[media_urls idempotency_key]).freeze

    class_attribute :default_params, default: {}.freeze

    class << self
      # Class-level defaults for every message this messenger builds.
      # Supported keys: from, category, provider, messaging_service,
      # metadata, validity_period.
      def default(value = nil)
        if value
          unknown = value.keys.map(&:to_sym) - DEFAULT_KEYS
          raise ArgumentError, "Unknown default(s): #{unknown.join(", ")}" if unknown.any?
          self.default_params = default_params.merge(value.symbolize_keys).freeze
        end
        default_params
      end
      alias_method :default_options=, :default

      def with(params)
        ParameterizedMessenger.new(self, params)
      end

      def messenger_name
        controller_path
      end

      def respond_to_missing?(name, include_all = false)
        action_methods.include?(name.to_s) || super
      end

      private

      def method_missing(name, *args, **kwargs, &block)
        if action_methods.include?(name.to_s)
          MessageDelivery.new(self, name, args:, kwargs:)
        else
          super
        end
      end
    end

    attr_writer :params

    def params
      @params ||= {}
    end

    # The message built by the last processed action, or nil when the
    # action returned without calling +text+.
    def message
      @_message if @_message_was_called
    end

    def process(method_name, *args, **kwargs)
      @_message_was_called = false
      @_message = nil
      super
    end

    def messenger_name
      self.class.messenger_name
    end

    # Build the message for this action. When +body+ is omitted the body is
    # rendered from app/views/<messenger_name>/<action>.text.erb.
    def text(to:, body: nil, from: nil, **options)
      unknown = options.keys - TEXT_OPTIONS
      raise ArgumentError, "Unknown option(s) for text: #{unknown.join(", ")}" if unknown.any?

      settings = self.class.default_params.merge(options)
      sender = Sender.resolve(from || settings[:from])
      recipient = Recipient.resolve(to)
      content = body.nil? ? render_to_string(action: action_name, formats: [:text]) : body

      @_message_was_called = true
      @_message = Message.new(
        to: recipient.phone,
        recipient:,
        from: sender.number,
        messaging_service: settings[:messaging_service] || sender.messaging_service,
        provider: settings[:provider] || sender.provider,
        body: BodyFormatter.call(content),
        media_urls: settings[:media_urls],
        category: settings[:category],
        metadata: (settings[:metadata] || {}).merge(params.fetch(:smswire_metadata, {})),
        validity_period: settings[:validity_period],
        idempotency_key: settings[:idempotency_key],
        consent_scope: settings[:consent_scope] || sender.consent_scope,
        messenger: self.class.name,
        action: action_name
      )
    end

    ActiveSupport.run_load_hooks(:smswire, self)
  end
end
