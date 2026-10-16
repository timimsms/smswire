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
  Result = Data.define(:status, :message, :receipt, :error) do
    def initialize(status:, message: nil, receipt: nil, error: nil)
      super
    end

    def accepted? = status == :accepted

    def failed? = status == :failed

    def rejected? = status.to_s.start_with?("rejected_")

    def suppressed? = status == :suppressed_by_interceptor

    def skipped? = status == :skipped

    def provider_id = receipt&.provider_id
  end
end
