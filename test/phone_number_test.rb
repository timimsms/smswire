require "test_helper"
require "phonelib"

class PhoneNumberTest < Smswire::TestCase
  def normalize(raw, **options) = Smswire::PhoneNumber.normalize(raw, **options)

  test "fallback normalizes NANP national formats" do
    with_config(phone_validator: :e164) do
      assert_equal "+14155552671", normalize("(415) 555-2671")
      assert_equal "+14155552671", normalize("1-415-555-2671")
      assert_equal "+14155552671", normalize("415.555.2671", region: "CA")
    end
  end

  test "fallback normalizes international formats" do
    with_config(phone_validator: :e164) do
      assert_equal "+442079460958", normalize("+44 20 7946 0958")
      assert_equal "+442079460958", normalize("0044 20 7946 0958")
    end
  end

  test "fallback rejects invalid input" do
    with_config(phone_validator: :e164) do
      assert_nil normalize("555-1234")
      assert_nil normalize("+1 055 555 2671")
      assert_nil normalize("call me")
      assert_nil normalize("")
      assert_nil normalize("020 7946 0958", region: "GB")
    end
  end

  test "phonelib handles national formats in any region" do
    with_config(phone_validator: :phonelib) do
      assert_equal "+442079460958", normalize("020 7946 0958", region: "GB")
      assert_nil normalize("12345", region: "GB")
    end
  end

  test "auto uses phonelib when it is loaded" do
    with_config(phone_validator: :auto) do
      assert Smswire::PhoneNumber.use_phonelib?
    end
  end
end
