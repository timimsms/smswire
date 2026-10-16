require "rails/generators/named_base"

module Smswire
  module Generators
    # bin/rails generate smswire:provider Acme
    class ProviderGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Create a Smswire provider adapter skeleton and register it."

      def create_provider
        template "provider.rb", File.join("app/sms_providers", class_path, "#{file_name}_provider.rb")
      end

      def create_test
        template "test.rb", File.join("test/sms_providers", class_path, "#{file_name}_provider_test.rb")
      end

      def register_provider
        initializer = File.join(destination_root, "config/initializers/smswire.rb")
        line = %(\nSmswire::Providers.register(:#{file_name}, "#{provider_class}")\n)
        if File.exist?(initializer)
          append_to_file "config/initializers/smswire.rb", line
        else
          say "Register the adapter in an initializer:#{line}"
        end
      end

      private

      def provider_class
        "#{class_name}Provider"
      end
    end
  end
end
