require "rails/generators/named_base"

module Smswire
  module Generators
    # bin/rails generate smswire:messenger Order shipped delivered
    class MessengerGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :actions, type: :array, default: [], banner: "action action"

      desc "Create a messenger with text templates, a preview, and a test."

      check_class_collision suffix: "Messenger"

      def create_application_messenger
        return if File.exist?(File.join(destination_root, "app/messengers/application_messenger.rb"))

        template "../../install/templates/application_messenger.rb", "app/messengers/application_messenger.rb"
      end

      def create_messenger
        template "messenger.rb", File.join("app/messengers", class_path, "#{file_name}.rb")
      end

      def create_templates
        actions.each do |action|
          @action = action
          template "view.text.erb", File.join("app/views", class_path, file_name, "#{action}.text.erb")
        end
      end

      def create_preview
        template "preview.rb", File.join("test/messengers/previews", class_path, "#{file_name}_preview.rb")
      end

      def create_test
        template "test.rb", File.join("test/messengers", class_path, "#{file_name}_test.rb")
      end

      private

      def file_name
        @_file_name ||= super.sub(/_messenger\z/i, "") + "_messenger"
      end

      def sample_number
        "+15555550100"
      end
    end
  end
end
