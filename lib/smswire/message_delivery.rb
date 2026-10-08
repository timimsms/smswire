require "delegate"

module Smswire
  # A lazy handle on a messenger action, like ActionMailer::MessageDelivery.
  # The action runs on first access to the message, on +deliver_now+, or
  # inside the job for +deliver_later+.
  class MessageDelivery < Delegator
    def initialize(messenger_class, action, args: [], kwargs: {}, params: {})
      @messenger_class = messenger_class
      @action = action
      @args = args
      @kwargs = kwargs
      @params = params
      @processed_messenger = nil
    end

    def __getobj__
      processed_messenger.message
    end

    def __setobj__(_object)
      raise NotImplementedError, "MessageDelivery cannot be reassigned"
    end

    def message
      __getobj__
    end

    def processed?
      !@processed_messenger.nil?
    end

    # Run the pipeline now and return a Smswire::Result.
    def deliver_now
      message = processed_messenger.message
      return Result.new(status: :skipped) if message.nil?

      Pipeline.call(message)
    end

    # Enqueue Smswire::DeliveryJob. The action runs again inside the job,
    # so arguments and params must be serializable by ActiveJob.
    def deliver_later(wait: nil, wait_until: nil, queue: nil, priority: nil)
      if processed?
        raise Error, "#{@messenger_class.name}##{@action} was accessed before deliver_later. " \
          "Changes made to the message would be lost; call deliver_later without reading it first."
      end

      options = {wait:, wait_until:, queue:, priority:}.compact
      DeliveryJob.set(options).perform_later(@messenger_class.name, @action.to_s, @params, @args, @kwargs)
    end

    private

    def processed_messenger
      @processed_messenger ||= @messenger_class.new.tap do |messenger|
        messenger.params = @params
        messenger.process(@action, *@args, **@kwargs)
      end
    end
  end
end
