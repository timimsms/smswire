module Smswire
  # A provider's report that a message changed status, parsed from a callback.
  StatusUpdate = Data.define(:provider_id, :status, :error_code, :error_message, :raw) do
    def initialize(provider_id:, status:, error_code: nil, error_message: nil, raw: {})
      super
    end
  end
end
