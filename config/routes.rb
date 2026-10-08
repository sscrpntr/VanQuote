Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]

  root "quotes#new"

  get "/profile", to: "profiles#show", as: :profile

  post "locale", to: "locales#update"

  resources :quotes, only: [ :index, :create, :show ] do
    get :public, on: :collection
  end

  resources :leads, only: [ :index, :edit, :update ]

  get "/admin", to: "admin#index", as: :admin
end
