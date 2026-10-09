Smswire::Engine.routes.draw do
  post "status/:provider", to: "status_callbacks#create", as: :status_callback
  post "inbound/:provider", to: "inbound_messages#create", as: :inbound_message

  # Development tools; each answers 404 unless enabled.
  get "previews", to: "previews#index", as: :previews
  get "previews/*path", to: "previews#show", as: :preview, format: false
  get "inbox", to: "inbox#index", as: :inbox
  post "inbox/inbound", to: "inbox#receive", as: :inbox_inbound
end
