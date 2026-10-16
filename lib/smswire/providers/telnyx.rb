require "base64"
require "bigdecimal"
require "json"
require "openssl"

module Smswire
  module Providers
    # Telnyx Messaging API v2 over REST. No SDK dependency.
    #
    #   Smswire.config.providers[:telnyx] = {
    #     api_key: "KEY...",
    #     public_key: "base64 key from Mission Control > Keys & Credentials",
    #     messaging_profile_id: "..."   # optional default; senders may set messaging_service
    #   }
    #
    # A sender's +messaging_service+ is sent as +messaging_profile_id+.
    # Credentials fall back to Rails.application.credentials.telnyx.
    # Telnyx does not accept a validity period here, so it is ignored.
    class Telnyx < Base
      API_URL = "https://api.telnyx.com/v2/messages".freeze
      SIGNATURE_TOLERANCE = 300
      ED25519_SPKI_PREFIX = ["302a300506032b6570032100"].pack("H*").freeze

      PERMANENT_REASONS = {
        "40300" => :opted_out,       # Blocked: recipient replied STOP
        "40310" => :invalid_number,  # Invalid 'to' address
        "40012" => :invalid_number,  # Invalid destination number
        "40001" => :unroutable,      # Not routable (landline or non-SMS)
        "40305" => :rejected,        # Invalid 'from' address
        "40013" => :rejected,        # Invalid source number
        "40311" => :authentication,  # Invalid profile secret
        "40313" => :authentication   # Missing profile secret
      }.freeze
      TRANSIENT_CODES = %w[40006 40008].freeze          # Recipient unavailable, undeliverable
      THROTTLED_CODES = %w[40002 40011 40016 40018].freeze # Spam throttle and carrier throughput limits

      STATUSES = {
        "queued" => :queued, "sending" => :accepted, "sent" => :sent, "delivered" => :delivered,
        "delivery_unconfirmed" => :sent, "sending_failed" => :failed, "delivery_failed" => :undelivered,
        "expired" => :undelivered
      }.freeze

      def deliver(message)
        response = HTTP.post_json(API_URL, payload_for(message),
          headers: {"Authorization" => "Bearer #{credential(:api_key)}"}, provider: name)
        handle(response)
      end

      BALANCE_URL = "https://api.telnyx.com/v2/balance".freeze

      def capabilities
        Set[:mms, :status_callbacks, :inbound, :messaging_services]
      end

      def verify_credentials!
        check_credentials_response(HTTP.get(BALANCE_URL, headers: {"Authorization" => "Bearer #{credential(:api_key)}"}, provider: name))
      end

      def payload_for(message)
        profile = message.messaging_service || options[:messaging_profile_id]
        if message.from.blank? && profile.blank?
          raise ConfigurationError, "Telnyx requires a from number or messaging_profile_id"
        end

        {
          to: message.to,
          from: message.from.presence,
          messaging_profile_id: profile.presence,
          text: message.body.presence,
          media_urls: message.media_urls.presence,
          webhook_url: message.status_callback_url || options[:webhook_url]
        }.compact
      end

      # Ed25519 over "<telnyx-timestamp>|<raw body>", checked against the
      # account public key, rejecting timestamps older than five minutes.
      def verify_signature!(request, url: nil)
        signature = request.headers["telnyx-signature-ed25519"].to_s
        timestamp = request.headers["telnyx-timestamp"].to_s
        raise SignatureError, "Missing Telnyx signature headers" if signature.empty? || timestamp.empty?
        raise SignatureError, "Stale Telnyx timestamp" if (Time.now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE

        verified = public_key.verify(nil, Base64.decode64(signature), "#{timestamp}|#{request.raw_post}")
        raise SignatureError, "Invalid Telnyx signature" unless verified
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        raise SignatureError, "Invalid Telnyx signature"
      end

      def parse_status_callback(request)
        event_type, payload = event(request)
        return nil unless %w[message.sent message.finalized].include?(event_type)

        recipient = Array(payload["to"]).first || {}
        error = Array(payload["errors"]).first || {}
        StatusUpdate.new(
          provider_id: payload["id"],
          status: STATUSES.fetch(recipient["status"].to_s, :accepted),
          error_code: error["code"]&.to_s,
          error_message: error["title"] || error["detail"],
          raw: payload
        )
      end

      def parse_inbound(request)
        event_type, payload = event(request)
        return nil unless event_type == "message.received"

        Inbound.new(
          provider_id: payload["id"],
          from: payload.dig("from", "phone_number"),
          to: Array(payload["to"]).first&.dig("phone_number"),
          body: payload["text"].to_s,
          messaging_service: payload["messaging_profile_id"],
          raw: payload
        )
      end

      private

      def handle(response)
        status = response.code.to_i
        json = HTTP.parse_json(response.body)
        return success(json["data"] || {}) if status.between?(200, 299)

        error = Array(json["errors"]).first || {}
        code = error["code"]&.to_s
        detail = "Telnyx #{status}#{" (#{code})" if code}: #{error["title"] || error["detail"] || response.message}"
        error_options = {provider: name, provider_code: code, http_status: status, raw: json}

        if status == 429 || THROTTLED_CODES.include?(code)
          retry_after = response["Retry-After"]&.to_i
          raise ThrottledError.new(detail, retry_after: retry_after&.positive? ? retry_after : nil, **error_options)
        elsif status >= 500 || TRANSIENT_CODES.include?(code)
          raise TransientError.new(detail, **error_options)
        elsif status == 401 || (status == 403 && code.nil?)
          raise PermanentError.new(detail, reason: :authentication, **error_options)
        else
          raise PermanentError.new(detail, reason: PERMANENT_REASONS.fetch(code, :rejected), **error_options)
        end
      end

      def success(data)
        recipient = Array(data["to"]).first || {}
        cost = data["cost"] || {}
        receipt(
          provider_id: data["id"],
          status: STATUSES.fetch(recipient["status"].to_s, :queued),
          segments: data["parts"]&.to_i,
          price_amount: (BigDecimal(cost["amount"].to_s) if cost["amount"].present?),
          price_currency: cost["currency"],
          raw: data
        )
      end

      def event(request)
        data = JSON.parse(request.raw_post.to_s)["data"] || {}
        [data["event_type"], data["payload"] || {}]
      rescue JSON::ParserError
        [nil, {}]
      end

      def public_key
        @public_key ||= OpenSSL::PKey.read(ED25519_SPKI_PREFIX + Base64.decode64(credential(:public_key)))
      end

      def credential(key)
        value = options[key] || rails_credentials&.dig(key)
        raise ConfigurationError, "Missing Telnyx #{key}" if value.blank?
        value
      end

      def rails_credentials
        return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
        ::Rails.application.credentials.telnyx&.to_h&.symbolize_keys
      end
    end
  end
end
