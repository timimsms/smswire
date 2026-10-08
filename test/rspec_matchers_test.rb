require "test_helper"
require "smswire/rspec"

class RSpecMatchersTest < Smswire::TestCase
  include ::RSpec::Matchers
  include Smswire::RSpec::Matchers

  NotMet = ::RSpec::Expectations::ExpectationNotMetError

  test "deliver_sms" do
    expect { OrderMessenger.literal("+14155552671", "shipped!").deliver_now }
      .to deliver_sms(to: "+14155552671", body: /shipped/)
    expect { OrderMessenger.literal("+14155552671", "x").deliver_now }.to deliver_sms.once
    expect { OrderMessenger.maybe("+14155552671", send: false).deliver_now }.not_to deliver_sms

    error = assert_raises(NotMet) do
      expect { OrderMessenger.literal("+14155552671", "x").deliver_now }.to deliver_sms(body: "y")
    end
    assert_includes error.message, %(body: "y")
  end

  test "deliver_sms with exact counts" do
    two = -> { 2.times { OrderMessenger.literal("+14155552671", "x").deliver_now } }
    expect(&two).to deliver_sms.exactly(2).times
    assert_raises(NotMet) { expect(&two).to deliver_sms.once }
  end

  test "have_enqueued_sms" do
    expect { OrderMessenger.literal("+14155552671", "x").deliver_later }
      .to have_enqueued_sms(OrderMessenger, :literal, args: ["+14155552671", "x"])
    expect { OrderMessenger.literal("+14155552671", "x").deliver_now }.not_to have_enqueued_sms

    assert_raises(NotMet) do
      expect { OrderMessenger.literal("+14155552671", "x").deliver_later }.to have_enqueued_sms(OrderMessenger, :shipped)
    end
  end
end
