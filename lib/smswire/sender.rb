module Smswire
  # A from-number or messaging service, with the provider that owns it.
  Sender = Data.define(:number, :messaging_service, :provider) do
    def initialize(number: nil, messaging_service: nil, provider: nil)
      super
    end

    def self.resolve(value)
      case value
      when nil then new
      when Sender then value
      when String then new(number: value)
      when Symbol
        options = Smswire.config.senders[value] || Smswire.config.senders[value.to_s]
        unless options
          raise ConfigurationError, "Unknown sender :#{value}. Define it in Smswire.config.senders."
        end
        options = options.to_h.symbolize_keys
        new(number: options[:number], messaging_service: options[:messaging_service], provider: options[:provider]&.to_sym)
      else
        raise ConfigurationError, "from: must be a phone number String or a sender Symbol, got #{value.class.name}"
      end
    end
  end
end
