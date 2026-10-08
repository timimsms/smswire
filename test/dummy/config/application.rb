require "rails"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "smswire"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "smswire-dummy"
    config.active_job.queue_adapter = :test
  end
end
