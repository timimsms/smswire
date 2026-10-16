class OrderMessenger < ApplicationMessenger
  def shipped(user)
    @user = user
    @order_number = params.fetch(:order_number)
    text to: user
  end

  def delivery_window(phone, window:)
    text to: phone, body: "Order #{params[:order_number]} arrives #{window}"
  end

  def promo(phone)
    text to: phone, from: :marketing, body: "Sale today", category: :marketing
  end

  def maybe(phone, send:)
    text(to: phone, body: "Maybe") if send
  end

  def literal(phone, body)
    text to: phone, body:
  end

  def deal(phone, body)
    text to: phone, body:, category: :marketing
  end
end
