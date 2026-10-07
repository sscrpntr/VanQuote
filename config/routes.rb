Rails.application.routes.draw do
  post "locale", to: "locales#update"
  post "locale", to: "locales#update"

  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]

  root "quotes#new"
  post "locale", to: "locales#update"

  resources :quotes, only: [ :create, :show ] do
    get :public, on: :collection
  end

  resources :leads, only: [ :index, :edit, :update ]
end
