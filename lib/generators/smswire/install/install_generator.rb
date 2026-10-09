require "rails/generators"
require "active_record"

module Smswire
  module Generators
    # bin/rails generate smswire:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Copy Smswire migrations, add an initializer and ApplicationMessenger, and mount the engine."

      def copy_migrations
        destination = File.join(destination_root, "db/migrate")
        FileUtils.mkdir_p(destination)
        copied = ActiveRecord::Migration.copy(destination, {smswire: Smswire::Engine.root.join("db/migrate").to_s})
        copied.each { |migration| say_status :create, "db/migrate/#{File.basename(migration.filename)}" }
        say_status :identical, "db/migrate (Smswire migrations already installed)" if copied.empty?
      end

      def create_initializer
        template "initializer.rb", "config/initializers/smswire.rb"
      end

      def create_application_messenger
        template "application_messenger.rb", "app/messengers/application_messenger.rb"
      end

      def mount_engine
        route %(mount Smswire::Engine => "/smswire")
      end

      def show_next_steps
        say <<~TEXT

          Smswire is installed. Next:
            1. bin/rails db:migrate
            2. Set provider credentials, senders, and callbacks_url in config/initializers/smswire.rb
            3. Point your provider's status and inbound webhooks at /smswire/status/<provider> and /smswire/inbound/<provider>
            4. bin/rails generate smswire:messenger Welcome greeting
        TEXT
      end
    end
  end
end
