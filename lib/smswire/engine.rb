require "rails/engine"
require "abstract_controller/railties/routes_helpers"

module Smswire
  # Mount for status callbacks:
  #
  #   mount Smswire::Engine => "/smswire"
  #
  # Install the migrations with +bin/rails smswire:install:migrations+.
  class Engine < ::Rails::Engine
    isolate_namespace Smswire

    ENVIRONMENT_PROVIDERS = {development: :log, test: :test}.freeze

    config.smswire = ActiveSupport::OrderedOptions.new

    # Runs after config/initializers so app settings win over defaults.
    initializer "smswire.configure", after: :load_config_initializers do |app|
      app.config.smswire.each { |key, value| Smswire.config.public_send(:"#{key}=", value) }
      Smswire.config.default_provider ||= ENVIRONMENT_PROVIDERS[::Rails.env.to_sym]
      Smswire.config.logger ||= ::Rails.logger
    end

    initializer "smswire.log_subscriber" do
      Smswire::LogSubscriber.attach_to :smswire
    end

    initializer "smswire.messenger" do |app|
      ActiveSupport.on_load(:smswire) do
        self.view_paths = ["#{::Rails.root}/app/views"]
        extend ::AbstractController::Railties::RoutesHelpers.with(app.routes, false)
        include app.routes.mounted_helpers
      end
    end
  end
end
