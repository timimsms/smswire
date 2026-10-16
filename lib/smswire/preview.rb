require "active_support/core_ext/class/subclasses"

module Smswire
  # Previews for messengers, like ActionMailer::Preview. Put them in
  # test/messengers/previews (or spec/messengers/previews) and open
  # <mount>/previews in development.
  #
  #   class OrderMessengerPreview < Smswire::Preview
  #     def shipped
  #       OrderMessenger.with(order: Order.first).shipped(User.first)
  #     end
  #   end
  #
  # Each public method returns a MessageDelivery. Nothing is sent.
  class Preview
    class << self
      def all
        load_previews
        descendants.reject { |preview| preview.name.nil? }.sort_by(&:preview_name)
      end

      def find(preview_name)
        all.find { |preview| preview.preview_name == preview_name }
      end

      def preview_name
        name.delete_suffix("Preview").underscore
      end

      def messages
        public_instance_methods(false).map(&:to_s).sort
      end

      def message_exists?(name)
        messages.include?(name.to_s)
      end

      # Runs the preview method and returns the built Smswire::Message, or
      # nil when the action did not call +text+. Interceptors are not run.
      def call(name)
        delivery = new.public_send(name)
        delivery.respond_to?(:message) ? delivery.message : delivery
      end

      private

      def load_previews
        Smswire.config.preview_paths.each do |path|
          Dir["#{path}/**/*_preview.rb"].sort.each { |file| require file }
        end
      end
    end
  end
end
