module Smswire
  # Sends keyword auto-replies. Uses the :compliance category, which skips
  # consent checks so the opt-out confirmation reaches an opted-out number.
  class KeywordMessenger < Base
    def reply(phone, kind, from: nil, messaging_service: nil, provider: nil)
      body = Smswire.config.keyword_reply(kind) or return

      text to: phone, body:, category: :compliance, from: (from unless messaging_service),
        messaging_service:, provider: provider&.to_sym
    end
  end
end
