require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/smswire/install/install_generator"
require "generators/smswire/messenger/messenger_generator"
require "generators/smswire/provider/provider_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Smswire::Generators::InstallGenerator
  destination File.expand_path("../tmp/generators/install", __dir__)

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "installs migrations, initializer, application messenger, and the mount" do
    run_generator

    assert_migration "db/migrate/create_smswire_deliveries.smswire.rb"
    assert_migration "db/migrate/create_smswire_consents_and_inbound_messages.smswire.rb"
    assert_file "config/initializers/smswire.rb", /Smswire.configure do \|config\|/
    assert_file "app/messengers/application_messenger.rb", /class ApplicationMessenger < Smswire::Base/
    assert_file "config/routes.rb", %r{mount Smswire::Engine => "/smswire"}
  end

  test "running twice does not duplicate migrations" do
    2.times { run_generator }
    assert_equal 2, Dir[File.join(destination_root, "db/migrate/*.rb")].size
  end
end

class MessengerGeneratorTest < Rails::Generators::TestCase
  tests Smswire::Generators::MessengerGenerator
  destination File.expand_path("../tmp/generators/messenger", __dir__)
  setup :prepare_destination

  test "creates the messenger, templates, preview, and test" do
    run_generator %w[Order shipped delivered]

    assert_file "app/messengers/application_messenger.rb"
    assert_file "app/messengers/order_messenger.rb" do |content|
      assert_match(/class OrderMessenger < ApplicationMessenger/, content)
      assert_match(/def shipped\(recipient\)/, content)
      assert_match(/def delivered\(recipient\)/, content)
    end
    assert_file "app/views/order_messenger/shipped.text.erb", /<%= @greeting %>, this is OrderMessenger#shipped./
    assert_file "test/messengers/previews/order_messenger_preview.rb", /class OrderMessengerPreview < Smswire::Preview/
    assert_file "test/messengers/order_messenger_test.rb", /assert_sms_delivered/
  end

  test "accepts a name that already ends in Messenger" do
    run_generator %w[OrderMessenger shipped]
    assert_file "app/messengers/order_messenger.rb", /class OrderMessenger < ApplicationMessenger/
  end
end

class ProviderGeneratorTest < Rails::Generators::TestCase
  ROOT = File.expand_path("../tmp/generators/provider-contract", __dir__)

  # Generate an adapter once and load it with its test, so the generated
  # code runs the provider contract as part of this suite.
  def self.load_generated_contract!
    return if defined?(::ContractcoProviderTest)

    FileUtils.rm_rf(ROOT)
    FileUtils.mkdir_p(File.join(ROOT, "config/initializers"))
    File.write(File.join(ROOT, "config/initializers/smswire.rb"), "")
    original_stdout, $stdout = $stdout, StringIO.new
    begin
      Smswire::Generators::ProviderGenerator.new(%w[Contractco], {}, destination_root: ROOT).invoke_all
    ensure
      $stdout = original_stdout
    end
    require File.join(ROOT, "app/sms_providers/contractco_provider.rb")
    Smswire::Providers.register(:contractco, "ContractcoProvider")
    require File.join(ROOT, "test/sms_providers/contractco_provider_test.rb")
    ::ContractcoProviderTest.include(DatabaseReset)
  end

  tests Smswire::Generators::ProviderGenerator
  destination File.expand_path("../tmp/generators/provider", __dir__)

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config/initializers"))
    File.write(File.join(destination_root, "config/initializers/smswire.rb"), "Smswire.configure { |config| }\n")
  end

  test "creates an adapter skeleton and registers it" do
    run_generator %w[Acme]
    assert_file "app/sms_providers/acme_provider.rb", /class AcmeProvider < Smswire::Providers::Base/
    assert_file "test/sms_providers/acme_provider_test.rb", /class AcmeProviderTest/
    assert_file "config/initializers/smswire.rb", /Smswire::Providers.register\(:acme, "AcmeProvider"\)/
  end
end

# Phase 4 acceptance: generated messenger output renders in previews with
# correct segment and encoding display.
class GeneratedMessengerPreviewTest < Smswire::IntegrationTest
  ROOT = File.expand_path("../tmp/generators/acceptance", __dir__)

  # Generate once per run, then load the output like an app would.
  def self.generate!
    return if defined?(::WelcomeMessenger)

    FileUtils.rm_rf(ROOT)
    Smswire::Generators::MessengerGenerator.new(%w[Welcome greet], {}, destination_root: ROOT).invoke_all
    require File.join(ROOT, "app/messengers/welcome_messenger.rb")
    require File.join(ROOT, "test/messengers/previews/welcome_messenger_preview.rb")
    ::WelcomeMessenger.prepend_view_path(File.join(ROOT, "app/views"))
  end

  setup { capture_io { self.class.generate! } }

  test "the generated preview renders with segment and encoding details" do
    get "/smswire/previews"
    assert_select "a[href='/smswire/previews/welcome_messenger/greet']"

    get "/smswire/previews/welcome_messenger/greet"
    assert_response :ok
    assert_select ".bubble", text: "Hi, this is WelcomeMessenger#greet."
    assert_select "[data-encoding]", text: "GSM-7"
    assert_select "[data-segments]", text: "1 segment"
  end

  test "the generated messenger delivers through the pipeline" do
    assert WelcomeMessenger.greet("+14155552671").deliver_now.accepted?
  end
end

ProviderGeneratorTest.load_generated_contract!
