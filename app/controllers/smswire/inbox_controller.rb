require "securerandom"

module Smswire
  # Development inbox: recent deliveries and inbound messages, plus a form
  # to simulate a reply such as STOP without a real provider.
  class InboxController < DevelopmentController
    self.enabled_by = :show_inbox

    LIMIT = 50

    def index
      @deliveries = Delivery.recent.limit(LIMIT)
      @inbound_messages = InboundMessage.recent.limit(LIMIT)
      @default_to = Smswire.config.senders.values.filter_map { |sender| sender.to_h.symbolize_keys[:number] }.first
    end

    def receive
      from = PhoneNumber.normalize(params[:from])
      if from.nil? || params[:body].blank?
        flash[:alert] = "Enter a valid From number and a message body."
        return redirect_to(inbox_path)
      end

      inbound = Inbound.new(provider_id: "inbox-#{SecureRandom.hex(8)}", from:, to: params[:to].presence, body: params[:body])
      record = InboundHandler.call(inbound, provider: Smswire.config.default_provider || :log)
      keyword = record&.reload&.keyword
      flash[:notice] = keyword ? "Received from #{from}; handled keyword #{keyword.upcase}." : "Received from #{from}."
      redirect_to inbox_path
    end
  end
end
