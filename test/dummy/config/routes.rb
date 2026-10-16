Rails.application.routes.draw do
  default_url_options host: "shop.example"
  resources :orders, only: :show
end
