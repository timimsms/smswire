require "digest"

module Smswire
  # A single outbound SMS. Built by Smswire::Base#text and passed through
  # the pipeline. Interceptors may change any attribute before delivery.
  class Message
    attr_accessor :to, :from, :body, :media_urls, :messaging_service, :provider,
      :category, :metadata, :validity_period, :messenger, :action, :recipient
    attr_reader :raw_to
    attr_writer :idempotency_key

    def initialize(to:, body:, from: nil, media_urls: [], messaging_service: nil, provider: nil,
      category: nil, metadata: {}, validity_period: nil, idempotency_key: nil,
      messenger: nil, action: nil, recipient: nil)
      @to = to
      @raw_to = to
      @from = from
      @body = body
      @media_urls = Array(media_urls)
      @messaging_service = messaging_service
      @provider = provider&.to_sym
      @category = (category || Smswire.config.default_category)&.to_sym
      @metadata = metadata || {}
      @validity_period = validity_period
      @idempotency_key = idempotency_key
      @messenger = messenger
      @action = action&.to_s
      @recipient = recipient
      @perform_deliveries = true
    end

    def perform_deliveries?
      @perform_deliveries
    end

    def cancel!
      @perform_deliveries = false
    end

    def analysis
      Segments.analyze(body)
    end

    def segments = analysis.segments

    def encoding = analysis.encoding

    def idempotency_key
      @idempotency_key || Digest::SHA256.hexdigest([messenger, action, to, body].join("\u0000"))[0, 32]
    end

    # Attributes safe to log or instrument. Never includes the body.
    def to_log_h
      {messenger:, action:, to:, from:, messaging_service:, provider:, category:,
       segments:, encoding:, media_count: media_urls.size}
    end

    def inspect
      "#<#{self.class.name} #{messenger}##{action} to=#{to.inspect} segments=#{segments} encoding=#{encoding}>"
    end
  end
end
