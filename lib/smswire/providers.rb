module Smswire
  module Providers
    @registry = {
      test: "Smswire::Providers::Test",
      log: "Smswire::Providers::Log",
      null: "Smswire::Providers::Null",
      twilio: "Smswire::Providers::Twilio"
    }

    class << self
      # Register a custom adapter: Smswire::Providers.register(:acme, "AcmeProvider").
      def register(name, klass)
        @registry[name.to_sym] = klass
      end

      def registered
        @registry.keys
      end

      def lookup(name)
        klass = @registry.fetch(name.to_sym) do
          raise ConfigurationError, "Unknown provider :#{name}. Registered: #{registered.join(", ")}"
        end
        klass.is_a?(String) ? klass.constantize : klass
      end

      def resolve(name = nil)
        name ||= Smswire.config.default_provider
        unless name
          raise ConfigurationError, "No SMS provider configured. Set Smswire.config.default_provider."
        end
        lookup(name).new(Smswire.config.provider_options(name), name: name.to_sym)
      end
    end
  end
end
