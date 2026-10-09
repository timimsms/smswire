module Smswire
  # Base for the development tools. Each subclass names the config flag
  # that enables it; when the flag is off the tool answers 404.
  class DevelopmentController < ActionController::Base
    layout "smswire/application"

    class_attribute :enabled_by

    before_action :require_enabled

    private

    def require_enabled
      head :not_found unless Smswire.config.public_send(enabled_by)
    end
  end
end
