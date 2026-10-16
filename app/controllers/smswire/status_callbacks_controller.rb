module Smswire
  # POST <mount>/status/:provider
  class StatusCallbacksController < WebhooksController
    def create
      handle_status || handle_inbound || head(:no_content)
    end
  end
end
