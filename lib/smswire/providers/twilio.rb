require "bigdecimal"

module Smswire
  module Providers
    # Twilio Programmable Messaging over the REST API. No SDK dependency.
    #
    #   Smswire.config.providers[:twilio] = {
    #     account_sid: "AC...", auth_token: "...",
    #     status_callback: "https://app.example.com/sms/status"  # optional
    #   }
    #
    # Credentials fall back to Rails.application.credentials.twilio.
    class Twilio < Base
      API_BASE = "https://api.twilio.com/2010-04-01".freeze

      PERMANENT_REASONS = {
        21211 => :invalid_number,  # Invalid 'To' number
        21214 => :invalid_number,  # 'To' number cannot be reached
        21217 => :invalid_number,  # Phone number does not appear to be valid
        21614 => :invalid_number,  # 'To' number is not a valid mobile number
        21610 => :opted_out,       # Recipient replied STOP
        21408 => :unroutable,      # Permission to send to this region not enabled
        21612 => :unroutable,      # Cannot route to this number
        21606 => :unroutable,      # 'From' number is not SMS capable
        20003 => :authentication   # Authentication failed
      }.freeze

      STATUSES = {
        "queued" => :queued, "scheduled" => :queued, "accepted" => :accepted,
        "sending" => :accepted, "sent" => :sent, "delivered" => :delivered,
        "undelivered" => :undelivered, "failed" => :failed, "read" => :read,
        "receiving" => :accepted, "received" => :delivered, "canceled" => :failed
      }.freeze

      def deliver(message)
        response = HTTP.post_form(messages_url, form_for(message), basic_auth: [account_sid, auth_token], provider: name)
        handle(response)
      end

      def capabilities
        Set[:mms, :status_callbacks, :inbound, :messaging_services]
      end

      def form_for(message)
        pairs = [["To", message.to]]
        if message.messaging_service
          pairs << ["MessagingServiceSid", message.messaging_service]
        elsif message.from
          pairs << ["From", message.from]
        else
          raise ConfigurationError, "Twilio requires a from number or messaging_service"
        end
        pairs << ["Body", message.body] if message.body.present?
        message.media_urls.each { |url| pairs << ["MediaUrl", url] }
        pairs << ["ValidityPeriod", message.validity_period.to_i.to_s] if message.validity_period
        pairs << ["StatusCallback", options[:status_callback]] if options[:status_callback]
        pairs
      end

      private

      def handle(response)
        status = response.code.to_i
        json = HTTP.parse_json(response.body)
        return success(json) if status.between?(200, 299)

        code = json["code"]
        detail = "Twilio #{status}#{" (#{code})" if code}: #{json["message"] || response.message}"
        error_options = {provider: name, provider_code: code&.to_s, http_status: status, raw: json}

        case status
        when 429
          retry_after = response["Retry-After"]&.to_i
          raise ThrottledError.new(detail, retry_after: retry_after&.positive? ? retry_after : nil, **error_options)
        when 500..599
          raise TransientError.new(detail, **error_options)
        when 401, 403
          raise PermanentError.new(detail, reason: :authentication, **error_options)
        else
          raise PermanentError.new(detail, reason: PERMANENT_REASONS.fetch(code, :rejected), **error_options)
        end
      end

      def success(json)
        receipt(
          provider_id: json["sid"],
          status: STATUSES.fetch(json["status"].to_s, :accepted),
          segments: json["num_segments"]&.to_i,
          price_amount: (BigDecimal(json["price"].to_s).abs if json["price"].present?),
          price_currency: json["price_unit"],
          raw: json
        )
      end

      def messages_url
        "#{options.fetch(:api_base, API_BASE)}/Accounts/#{account_sid}/Messages.json"
      end

      def account_sid = credential(:account_sid)

      def auth_token = credential(:auth_token)

      def credential(key)
        value = options[key] || rails_credentials&.dig(key)
        raise ConfigurationError, "Missing Twilio #{key}" if value.blank?
        value
      end

      def rails_credentials
        return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
        ::Rails.application.credentials.twilio&.to_h&.symbolize_keys
      end
    end
  end
end
