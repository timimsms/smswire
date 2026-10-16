module Smswire
  # Detects STOP / START / HELP style keywords in inbound messages, updates
  # consent, and sends the configured auto-reply.
  #
  # A keyword matches only when it is the whole message, ignoring case,
  # spaces, and surrounding punctuation, so "Opt out." matches OPTOUT and
  # "stop all" matches STOPALL. Free-text requests such as "please stop
  # texting me" are recorded but not matched; see docs/guides/compliance.md.
  module Keywords
    STORED = {opt_out: "stop", opt_in: "start", help: "help"}.freeze

    module_function

    # Returns [kind, word] or nil.
    def classify(body)
      word = body.to_s.strip.gsub(/\A[^[:alnum:]]+|[^[:alnum:]]+\z/, "").gsub(/[[:space:]-]+/, "").upcase
      return nil if word.empty?

      Smswire.config.keywords.each do |kind, words|
        return [kind.to_sym, word] if words.map { |candidate| candidate.upcase.delete(" -") }.include?(word)
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
        if word == "STOPALL" || Smswire.config.opt_out_all_scopes
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
