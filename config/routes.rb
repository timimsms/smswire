Smswire::Engine.routes.draw do
  post "status/:provider", to: "status_callbacks#create", as: :status_callback
end
