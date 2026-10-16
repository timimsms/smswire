require "test_helper"

class LogSubscriberTest < Smswire::TestCase
  def capture
    output = StringIO.new
    with_config(logger: Logger.new(output)) { yield }
    output.string
  end

  test "logs deliveries with masked numbers and no body" do
    log = capture { OrderMessenger.literal("+14155552671", "secret 5555").deliver_now }
    assert_match(/SMS OrderMessenger#literal to \+1\*{6}2671 via test: accepted SMtest\w+ \(1 segment\(s\)/, log)
    refute_includes log, "secret"
    refute_includes log, "4155552671"
  end

  test "logs rejections and transient errors" do
    log = capture do
      OrderMessenger.literal("bogus", "x").deliver_now
      Smswire::Providers::Test.fail_next(Smswire::TransientError.new("network down"))
      assert_raises(Smswire::TransientError) { OrderMessenger.literal("+14155552671", "y").deliver_now }
    end
    assert_includes log, "not sent: rejected_invalid_number"
    assert_includes log, "raised Smswire::TransientError: network down"
  end
end
