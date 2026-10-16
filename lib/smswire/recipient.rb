module Smswire
  # The resolved target of a message: the phone number as given, plus the
  # originating record and its time zone when available.
  Recipient = Data.define(:phone, :record, :time_zone) do
    def initialize(phone:, record: nil, time_zone: nil)
      super
    end

    # Resolution order: Recipient, String, the configured resolver, then
    # +phone_number+ on the object.
    def self.resolve(value)
      case value
      when Recipient
        value
      when String
        raise UnresolvableRecipient, "Recipient phone number is blank" if value.blank?
        new(phone: value)
      when nil
        raise UnresolvableRecipient, "No recipient given"
      else
        phone = phone_for(value)
        if phone.blank?
          raise UnresolvableRecipient, "Could not resolve a phone number from #{value.class.name}"
        end
        new(phone: phone.to_s, record: value, time_zone: (value.time_zone if value.respond_to?(:time_zone)))
      end
    end

    def self.phone_for(value)
      if (resolver = Smswire.config.recipient_resolver)
        resolver.call(value)
      elsif value.respond_to?(:phone_number)
        value.phone_number
      end
    end
    private_class_method :phone_for
  end
end
