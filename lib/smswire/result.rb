module Smswire
  # The outcome of running a message through the delivery pipeline.
  #
  # Statuses:
  #   :accepted                    provider accepted the message
  #   :failed                      provider permanently refused it (see +error+)
  #   :rejected_invalid_number     recipient is not a valid E.164 number
  #   :rejected_empty_body         no body and no media
  #   :suppressed_by_interceptor   an interceptor cancelled delivery
  #   :skipped                     the messenger action did not call +text+
  #   :duplicate                   an identical message was sent inside the dedupe window
  #
  # +delivery+ is the Smswire::Delivery row when persistence is enabled.
  Result = Data.define(:status, :message, :receipt, :error, :delivery) do
    def initialize(status:, message: nil, receipt: nil, error: nil, delivery: nil)
      super
    end

    def accepted? = status == :accepted

    def failed? = status == :failed

    def rejected? = status.to_s.start_with?("rejected_")

    def suppressed? = status == :suppressed_by_interceptor

    def skipped? = status == :skipped

    def duplicate? = status == :duplicate

    def provider_id = receipt&.provider_id
  end
end
