require "bigdecimal"
require "digest/md5"
require "openssl"

module Smswire
  module Providers
    # Vonage SMS API over REST. No SDK dependency.
    #
    #   Smswire.config.providers[:vonage] = {
    #     api_key: "...", api_secret: "...",
    #     signature_secret: "...",       # required to verify webhooks
    #     signature_method: "sha256"     # md5hash (Vonage's default), md5, sha1, sha256, or sha512
    #   }
    #
    # Set the dashboard webhook method to POST. Long messages are billed as
    # several parts; the receipt keeps the first part's message id, so
    # delivery receipts for later parts are acknowledged but not matched.
    # Prices are recorded in the account currency, which the API does not name.
    # Credentials fall back to Rails.application.credentials.vonage.
    class Vonage < Base
      API_URL = "https://rest.nexmo.com/sms/json".freeze
      SIGNATURE_METHODS = %w[md5hash md5 sha1 sha256 sha512].freeze
      SIGNATURE_TOLERANCE = 300

      # Send response status codes.
      PERMANENT_REASONS = {
        "4" => :authentication,  # Invalid credentials
        "14" => :authentication, # Invalid signature
        "32" => :authentication, # Signature and API secret disallowed
        "6" => :invalid_number,  # Invalid message (unrecognized number prefix)
        "33" => :invalid_number, # Number de-activated
        "7" => :unroutable,      # Number barred; may include opt-outs but is not specific to them
        "29" => :unroutable      # Non-whitelisted destination (demo account)
      }.freeze
      THROTTLED_CODES = %w[1].freeze
      TRANSIENT_CODES = %w[5].freeze

      # Delivery receipt statuses.
      STATUSES = {
        "accepted" => :accepted, "buffered" => :sent, "delivered" => :delivered, "expired" => :undelivered,
        "failed" => :undelivered, "rejected" => :failed, "unknown" => :sent
      }.freeze

      def deliver(message)
        response = HTTP.post_form(API_URL, form_for(message), provider: name)
        handle(response)
      end

      BALANCE_URL = "https://rest.nexmo.com/account/get-balance".freeze

      def capabilities
        Set[:status_callbacks, :inbound]
      end

      def verify_credentials!
        query = URI.encode_www_form(api_key: credential(:api_key), api_secret: credential(:api_secret))
        check_credentials_response(HTTP.get("#{BALANCE_URL}?#{query}", provider: name))
      end

      def form_for(message)
        raise ConfigurationError, "Vonage requires a from number or sender id" if message.from.blank?

        pairs = [
          ["api_key", credential(:api_key)], ["api_secret", credential(:api_secret)],
          ["to", message.to.delete_prefix("+")], ["from", message.from.delete_prefix("+")],
          ["text", message.body.to_s], ["type", (message.encoding == :ucs2) ? "unicode" : "text"]
        ]
        pairs << ["ttl", (message.validity_period.to_i * 1000).to_s] if message.validity_period
        if (callback = message.status_callback_url || options[:callback])
          pairs << ["status-report-req", "1"] << ["callback", callback]
        end
        pairs
      end

      # Vonage signs webhook parameters as sorted "&key=value" pairs with
      # "&" and "=" in values replaced by "_", then hashes with the
      # signature secret. Timestamps older than five minutes are rejected.
      def verify_signature!(request, url: nil)
        params = request.request_parameters.to_h.transform_keys(&:to_s)
        signature = params.delete("sig").to_s
        raise SignatureError, "Missing Vonage sig parameter" if signature.empty?
        if params["timestamp"].present? && (Time.now.to_i - params["timestamp"].to_i).abs > SIGNATURE_TOLERANCE
          raise SignatureError, "Stale Vonage timestamp"
        end

        expected = self.class.signature(params, secret: signature_secret, method: signature_method)
        return if ActiveSupport::SecurityUtils.secure_compare(expected.downcase, signature.downcase)

        raise SignatureError, "Invalid Vonage signature"
      end

      def self.signature(params, secret:, method:)
        data = params.sort.map { |key, value| "&#{key}=#{value.to_s.tr("&=", "__")}" }.join
        if method == "md5hash"
          Digest::MD5.hexdigest("#{data}#{secret}")
        else
          OpenSSL::HMAC.hexdigest(method, secret, data).upcase
        end
      end

      def parse_status_callback(request)
        params = request.request_parameters
        return nil if params["status"].blank?

        err_code = params["err-code"].to_s
        StatusUpdate.new(
          provider_id: params["messageId"],
          status: STATUSES.fetch(params["status"].to_s, :sent),
          error_code: (err_code unless err_code.empty? || err_code == "0"),
          raw: params.to_h
        )
      end

      def parse_inbound(request)
        params = request.request_parameters
        return nil unless params.key?("text") && params["msisdn"].present?

        Inbound.new(
          provider_id: params["messageId"],
          from: international(params["msisdn"]),
          to: international(params["to"]),
          body: params["text"].to_s,
          raw: params.to_h
        )
      end

      private

      def handle(response)
        status = response.code.to_i
        json = HTTP.parse_json(response.body)
        raise TransientError.new("Vonage #{status}", provider: name, http_status: status) if status >= 500
        if status == 429
          raise ThrottledError.new("Vonage 429", provider: name, http_status: status)
        end

        parts = Array(json["messages"])
        failed = parts.find { |part| part["status"].to_s != "0" }
        return success(parts) if status.between?(200, 299) && parts.any? && failed.nil?

        code = failed&.dig("status")&.to_s
        detail = "Vonage #{status}#{" (#{code})" if code}: #{failed&.dig("error-text") || response.message}"
        error_options = {provider: name, provider_code: code, http_status: status, raw: json}
        if THROTTLED_CODES.include?(code)
          raise ThrottledError.new(detail, **error_options)
        elsif TRANSIENT_CODES.include?(code)
          raise TransientError.new(detail, **error_options)
        else
          raise PermanentError.new(detail, reason: PERMANENT_REASONS.fetch(code, :rejected), **error_options)
        end
      end

      def success(parts)
        prices = parts.filter_map { |part| part["message-price"].presence }
        receipt(
          provider_id: parts.first["message-id"],
          status: :accepted,
          segments: parts.size,
          price_amount: (prices.sum { |price| BigDecimal(price.to_s) } if prices.any?),
          raw: {"messages" => parts}
        )
      end

      def international(number)
        number = number.to_s
        number.match?(/\A\d+\z/) ? "+#{number}" : number
      end

      def signature_secret
        credential(:signature_secret)
      rescue ConfigurationError
        raise SignatureError, "Set providers[:vonage][:signature_secret] to verify Vonage webhooks"
      end

      def signature_method
        method = (options[:signature_method] || rails_credentials&.dig(:signature_method) || "md5hash").to_s
        raise ConfigurationError, "Unknown Vonage signature_method #{method}" unless SIGNATURE_METHODS.include?(method)
        method
      end

      def credential(key)
        value = options[key] || rails_credentials&.dig(key)
        raise ConfigurationError, "Missing Vonage #{key}" if value.blank?
        value
      end

      def rails_credentials
        return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
        ::Rails.application.credentials.vonage&.to_h&.symbolize_keys
      end
    end
  end
end
