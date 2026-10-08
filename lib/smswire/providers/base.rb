module Smswire
  module Providers
    # Adapter contract. Subclasses implement +deliver(message)+ and return a
    # Smswire::Receipt, raising Smswire::TransientError,
    # Smswire::ThrottledError, or Smswire::PermanentError on failure.
    class Base
      attr_reader :options, :name

      def initialize(options = {}, name: nil)
        @options = options.to_h.symbolize_keys
        @name = name || self.class.name.demodulize.underscore.to_sym
      end

      def deliver(message)
        raise NotImplementedError, "#{self.class.name} must implement #deliver"
      end

      def capabilities
        Set.new
      end

      private

      def receipt(**attributes)
        Receipt.new(provider: name, **attributes)
      end
    end
  end
end
