Smswire::Engine.routes.draw do
  post "status/:provider", to: "status_callbacks#create", as: :status_callback
  post "inbound/:provider", to: "inbound_messages#create", as: :inbound_message
end
