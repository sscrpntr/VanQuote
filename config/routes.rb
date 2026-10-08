Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]

  root "quotes#new"

  resource :profile, only: [ :show, :update ], controller: "profiles"

  post "locale", to: "locales#update"

  resources :quotes, only: [ :index, :create, :show ] do
    get :public, on: :collection
  end

  resources :leads, only: [ :index, :edit, :update ]

  get "/admin", to: "admin#index", as: :admin
end
