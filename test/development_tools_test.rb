require "test_helper"

class DevelopmentToolsTest < Smswire::IntegrationTest
  test "previews index lists previews and their methods" do
    get "/smswire/previews"
    assert_response :ok
    assert_select "h2", text: "OrderMessenger"
    assert_select "a[href='/smswire/previews/order_messenger/shipped']", text: "shipped"
  end

  test "a preview renders the body, encoding, and segments without sending" do
    get "/smswire/previews/order_messenger/shipped"
    assert_response :ok
    assert_select(".bubble") do |bubble|
      assert_equal "Hi Ada!\nOrder R100 has shipped.\n\nTrack it: http://shop.example/orders/R100", bubble.text
    end
    assert_select "[data-encoding]", text: "GSM-7"
    assert_select "[data-segments]", text: "1 segment"
    assert_select "[data-non-gsm]", count: 0
    assert_empty sms_deliveries
    assert_equal 0, Smswire::Delivery.count
  end

  test "a preview explains UCS-2 and multi-segment messages" do
    get "/smswire/previews/order_messenger/unicode"
    assert_select "[data-encoding]", text: "UCS-2"
    assert_select "[data-non-gsm] code", text: "☕"

    get "/smswire/previews/order_messenger/long"
    assert_select "[data-segments]", text: "2 segments"
    assert_includes response.body, "200 units, 106 left in this segment"
  end

  test "raw text and skipped actions" do
    get "/smswire/previews/order_messenger/unicode", params: {raw: 1}
    assert_equal "Café ☕ is ready", response.body

    get "/smswire/previews/order_messenger/skipped"
    assert_includes response.body, "returned without calling"
  end

  test "unknown previews are not found" do
    get "/smswire/previews/order_messenger/nope"
    assert_response :not_found
    get "/smswire/previews/missing/shipped"
    assert_response :not_found
  end

  test "development deliveries appear in the inbox" do
    with_config(default_provider: :log, logger: Logger.new(nil)) do
      OrderMessenger.literal("+14155552671", "Your order shipped").deliver_now
    end
    get "/smswire/inbox"
    assert_response :ok
    assert_select "td.body", text: "Your order shipped"
    assert_select "td.status-accepted", text: "accepted"
  end

  test "the inbox simulates replies through keyword handling" do
    post "/smswire/inbox/inbound", params: {from: "(415) 555-2671", to: "+15005550006", body: "STOP"}
    assert_redirected_to "/smswire/inbox"
    follow_redirect!
    assert_select ".flash", text: "Received from +14155552671; handled keyword STOP."
    assert_equal "opted_out", Smswire::Consent.status_for("+14155552671")

    perform_enqueued_jobs
    assert_match(/unsubscribed/, sms_deliveries.sole.body)

    post "/smswire/inbox/inbound", params: {from: "nope", body: "hi"}
    follow_redirect!
    assert_select ".flash", text: /valid From number/
  end

  test "development tools are hidden when disabled" do
    with_config(show_previews: false, show_inbox: false) do
      get "/smswire/previews"
      assert_response :not_found
      get "/smswire/inbox"
      assert_response :not_found
      post "/smswire/inbox/inbound", params: {from: "+14155552671", body: "STOP"}
      assert_response :not_found
    end
    assert_equal 0, Smswire::Consent.count
  end
end
