class OrderMessengerPreview < Smswire::Preview
  def shipped
    OrderMessenger.with(order_number: "R100").shipped(Struct.new(:name, :phone_number).new("Ada", "+14155552671"))
  end

  def unicode
    OrderMessenger.literal("+14155552671", "Café ☕ is ready")
  end

  def long
    OrderMessenger.literal("+14155552671", "x" * 200)
  end

  def skipped
    OrderMessenger.maybe("+14155552671", send: false)
  end
end
