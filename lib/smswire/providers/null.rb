module Smswire
  module Providers
    # Accepts and discards every message.
    class Null < Base
      def deliver(message)
        receipt(status: :accepted, segments: message.segments)
      end
    end
  end
end
