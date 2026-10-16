module Smswire
  # Detects STOP / START / HELP style keywords in inbound messages, updates
  # consent, and sends the configured auto-reply.
  #
  # A keyword matches only when it is the whole message, ignoring case,
  # surrounding whitespace, and surrounding punctuation, which is how
  # carriers and Twilio match them.
  module Keywords
    STORED = {opt_out: "stop", opt_in: "start", help: "help"}.freeze

    module_function

    # Returns [kind, word] or nil.
    def classify(body)
      word = body.to_s.strip.gsub(/\A[^[:alnum:]]+|[^[:alnum:]]+\z/, "").upcase
      return nil if word.empty?

      Smswire.config.keywords.each do |kind, words|
        return [kind.to_sym, word] if words.map(&:upcase).include?(word)
      end
      nil
    end

    def handle(record, inbound, provider:)
      kind, word = classify(record.body)
      return nil unless kind

      phone = record.from_number
      scope = Consent.scope_for_sender(number: record.to_number, messaging_service: record.messaging_service)
      case kind
      when :opt_out
        if word == "STOPALL"
          Consent.opt_out_everywhere!(phone, source: :keyword, keyword: word)
        else
          Consent.opt_out!(phone, scope:, source: :keyword, keyword: word)
        end
      when :opt_in
        Consent.opt_in!(phone, scope:, source: :keyword, keyword: word)
      end

      unless inbound.provider_keyword
        KeywordMessenger.reply(phone, kind.to_s, from: record.to_number,
          messaging_service: record.messaging_service, provider: provider.to_s).deliver_later
      end

      record.update!(keyword: STORED.fetch(kind), handled_at: Time.current)
      kind
    end
  end
end
