module Smswire
  # Shared provider webhook handling. Each endpoint tries its own kind of
  # event first and falls back to the other, so a provider that posts every
  # event to one URL (Telnyx messaging profiles do) is handled either way.
  # Signed, well-formed requests always get a 2xx so providers do not retry.
  class WebhooksController < ActionController::Base
    skip_forgery_protection

    before_action :load_provider
    before_action :verify_signature

    private

    def load_provider
      @provider = Providers.resolve(params[:provider])
      head(:not_found) unless (@provider.capabilities & %i[status_callbacks inbound]).any?
    rescue ConfigurationError
      head :not_found
    end

    def verify_signature
      return unless Smswire.config.verify_callback_signatures

      @provider.verify_signature!(request, url: Callbacks.request_url(request))
    rescue SignatureError => error
      Smswire.logger.warn("[Smswire] Rejected #{@provider.name} webhook: #{error.message}")
      head :forbidden
    end

    def handle_status
      return false unless @provider.capabilities.include?(:status_callbacks)

      update = @provider.parse_status_callback(request) or return false
      StatusHandler.call(update, provider: @provider.name, delivery_id: params[:delivery_id])
      head :no_content
      true
    end

    def handle_inbound
      return false unless @provider.capabilities.include?(:inbound)

      inbound = @provider.parse_inbound(request) or return false
      InboundHandler.call(inbound, provider: @provider.name)
      body, content_type = @provider.inbound_response
      body ? render(plain: body, content_type:) : head(:no_content)
      true
    end
  end
end
