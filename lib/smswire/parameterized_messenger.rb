module Smswire
  # Returned by Smswire::Base.with(params). Actions called on it build a
  # MessageDelivery whose messenger instance sees +params+.
  class ParameterizedMessenger
    def initialize(messenger, params)
      @messenger = messenger
      @params = params
    end

    def respond_to_missing?(name, include_all = false)
      @messenger.action_methods.include?(name.to_s) || super
    end

    private

    def method_missing(name, *args, **kwargs, &block)
      if @messenger.action_methods.include?(name.to_s)
        MessageDelivery.new(@messenger, name, args:, kwargs:, params: @params)
      else
        super
      end
    end
  end
end
