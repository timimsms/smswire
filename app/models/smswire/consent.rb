module Smswire
  # A phone number's messaging consent within a scope. The scope is
  # "default" unless a sender sets +consent_scope+, which lets separate
  # programs (for example two brands on two numbers) keep separate consent.
  #
  #   Smswire::Consent.opt_in!("+15551234567", source: :web_form,
  #     metadata: {ip: request.remote_ip, form: "checkout", copy: terms_text})
  #   Smswire::Consent.status_for("+15551234567")  # => "opted_in"
  class Consent < ApplicationRecord
    DEFAULT_SCOPE = "default".freeze
    STATUSES = %w[opted_in opted_out pending unknown].freeze

    enum :status, STATUSES.index_with(&:itself)

    class << self
      def status_for(phone, scope: DEFAULT_SCOPE)
        find_by(phone: normalize!(phone), scope: scope.to_s)&.status || "unknown"
      end

      def opt_in!(phone, source:, scope: DEFAULT_SCOPE, keyword: nil, metadata: {})
        record!(phone, scope, {status: "opted_in", opted_in_at: Time.current}, source:, keyword:, metadata:)
      end

      def opt_out!(phone, source:, scope: DEFAULT_SCOPE, keyword: nil, metadata: {})
        record!(phone, scope, {status: "opted_out", opted_out_at: Time.current}, source:, keyword:, metadata:)
      end

      # STOPALL: opt out of every scope this number has, plus every scope
      # the configured senders use.
      def opt_out_everywhere!(phone, source:, keyword: nil)
        number = normalize!(phone)
        scopes = (where(phone: number).pluck(:scope) + Smswire.config.consent_scopes).uniq
        scopes.map { |scope| opt_out!(number, scope:, source:, keyword:) }
      end

      # The consent scope of the configured sender that owns +number+ or
      # +messaging_service+, used for inbound keywords.
      def scope_for_sender(number: nil, messaging_service: nil)
        Smswire.config.senders.each_value do |options|
          options = options.to_h.symbolize_keys
          matched = (number.present? && options[:number] == number) ||
            (messaging_service.present? && options[:messaging_service] == messaging_service)
          return (options[:consent_scope] || DEFAULT_SCOPE).to_s if matched
        end
        DEFAULT_SCOPE
      end

      private

      def normalize!(phone)
        PhoneNumber.normalize(phone) || raise(ArgumentError, "Invalid phone number: #{phone.inspect}")
      end

      def record!(phone, scope, attributes, source:, keyword:, metadata:)
        retried = false
        begin
          consent = find_or_initialize_by(phone: normalize!(phone), scope: scope.to_s)
          consent.assign_attributes(attributes.merge(source: source.to_s))
          consent.assign_attributes(last_keyword: keyword, last_keyword_at: Time.current) if keyword
          consent.metadata = (consent.metadata || {}).merge(metadata.deep_stringify_keys) if metadata.present?
          consent.save!
          consent
        rescue ActiveRecord::RecordNotUnique
          raise if retried
          retried = true
          retry
        end
      end
    end
  end
end
