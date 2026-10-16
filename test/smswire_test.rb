require "test_helper"

class SmswireTest < Smswire::TestCase
  test "has a version number" do
    refute_nil Smswire::VERSION
  end

  test "railtie defaults the provider to :test in the test environment" do
    assert_equal :test, Smswire.config.default_provider
  end

  test "railtie keeps settings from config/initializers" do
    assert_equal "+15005550006", Smswire.config.senders[:transactional][:number]
  end

  test "railtie points messengers at the app views" do
    assert_includes OrderMessenger.view_paths.map(&:to_s), Rails.root.join("app/views").to_s
  end

  test "rejects invalid configuration values" do
    assert_raises(Smswire::ConfigurationError) { Smswire::Configuration.new.body_whitespace = :tidy }
    assert_raises(Smswire::ConfigurationError) { Smswire::Configuration.new.phone_validator = :magic }
  end

  test "registers and unregisters interceptors and observers once" do
    hook = Object.new
    2.times { Smswire.register_interceptor(hook) }
    2.times { Smswire.register_observer(hook) }
    assert_equal 1, Smswire.config.interceptors.count(hook)
    assert_equal 1, Smswire.config.observers.count(hook)
  ensure
    Smswire.unregister_interceptor(hook)
    Smswire.unregister_observer(hook)
  end
end
