ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

ActiveRecord::Migration.verbose = false
ActiveRecord::MigrationContext.new(File.expand_path("../db/migrate", __dir__)).migrate
require "minitest/autorun"
require "webmock/minitest"

Smswire.config.phone_validator = :e164

User = Struct.new(:name, :phone_number)

module ConfigHelpers
  # Temporarily override Smswire.config attributes for one test.
  def with_config(**overrides)
    config = Smswire.config
    previous = overrides.keys.to_h { |key| [key, config.public_send(key)] }
    overrides.each { |key, value| config.public_send(:"#{key}=", value) }
    yield
  ensure
    previous&.each { |key, value| config.public_send(:"#{key}=", value) }
  end

  def twilio_url
    "https://api.twilio.com/2010-04-01/Accounts/ACtest/Messages.json"
  end

  def twilio_success(sid: "SM123", status: "queued", segments: "1")
    {status: 201, headers: {"Content-Type" => "application/json"},
     body: {sid:, status:, num_segments: segments, price: nil, price_unit: "USD"}.to_json}
  end
end

class Smswire::TestCase < ActiveSupport::TestCase
  include Smswire::TestHelper
  include ConfigHelpers

  setup { [Smswire::Delivery, Smswire::Consent, Smswire::InboundMessage].each(&:delete_all) }
end
