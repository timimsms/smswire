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

      # Raise Smswire::SignatureError unless +request+ was signed by the
      # provider. +url+ is the public URL the provider posted to.
      def verify_signature!(request, url:)
        raise NotImplementedError, "#{self.class.name} does not support callbacks"
      end

      # Return a Smswire::Inbound for an inbound message webhook.
      def parse_inbound(request)
        raise NotImplementedError, "#{self.class.name} does not support inbound messages"
      end

      # [body, content_type] to answer an inbound webhook with, or nil for 204.
      def inbound_response
        nil
      end

      # Return a Smswire::StatusUpdate for a status callback request.
      def parse_status_callback(request)
        raise NotImplementedError, "#{self.class.name} does not support status callbacks"
      end

      private

      def receipt(**attributes)
        Receipt.new(provider: name, **attributes)
      end
    end
  end
end
