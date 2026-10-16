require "zeitwerk"
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/numeric/time"
require "active_job"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("http" => "HTTP", "rspec" => "RSpec")
loader.ignore(
  "#{__dir__}/generators",
  "#{__dir__}/smswire/errors.rb",
  "#{__dir__}/smswire/engine.rb",
  "#{__dir__}/smswire/rspec.rb"
)
loader.setup

require_relative "smswire/errors"

# Smswire is the production SMS layer for Rails: messenger classes and
# templates, a provider-agnostic message object, a delivery pipeline with
# typed outcomes, provider adapters, retries, and test helpers.
#
# See docs/SPEC.md for the full design.
module Smswire
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    def logger
      config.logger || ActiveSupport::Logger.new($stdout)
    end

    # Interceptors respond to +delivering_sms(message)+. They run after the
    # recipient is normalized and before the provider is called, and may
    # mutate the message or cancel it with +message.cancel!+.
    def register_interceptor(interceptor)
      config.interceptors << interceptor unless config.interceptors.include?(interceptor)
    end

    def unregister_interceptor(interceptor)
      config.interceptors.delete(interceptor)
    end

    # Observers respond to +delivered_sms(result)+. They are called with
    # every pipeline outcome except transient errors, which raise.
    def register_observer(observer)
      config.observers << observer unless config.observers.include?(observer)
    end

    def unregister_observer(observer)
      config.observers.delete(observer)
    end
  end
end

require_relative "smswire/engine" if defined?(Rails::Railtie)
