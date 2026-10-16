module Smswire
  # Receives inbound messages at POST <mount>/inbound/:provider, records
  # them once per provider message id, and handles compliance keywords.
  # Apps can build two-way messaging with an observer that implements
  # +sms_received(inbound_message)+.
  class InboundMessagesController < ActionController::Base
    skip_forgery_protection

    def create
      provider = Providers.resolve(params[:provider])
      return head(:not_found) unless provider.capabilities.include?(:inbound)

      if Smswire.config.verify_callback_signatures
        provider.verify_signature!(request, url: Callbacks.request_url(request))
      end

      InboundHandler.call(provider.parse_inbound(request), provider: provider.name)

      body, content_type = provider.inbound_response
      body ? render(plain: body, content_type:) : head(:no_content)
    rescue ConfigurationError
      head :not_found
    rescue SignatureError
      head :forbidden
    end
  end
end
