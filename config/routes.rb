Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  root "quotes#new"

  resources :quotes, only: [ :create, :show ] do
    get :public, on: :collection
  end

  resources :leads, only: [ :index, :update ]
end
