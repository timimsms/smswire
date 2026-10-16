module Smswire
  # POST <mount>/inbound/:provider. Apps can build two-way messaging with
  # an observer that implements +sms_received(inbound_message)+.
  class InboundMessagesController < WebhooksController
    def create
      handle_inbound || handle_status || head(:no_content)
    end
  end
end
