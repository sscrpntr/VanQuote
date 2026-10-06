Rails.application.routes.draw do
  root "quotes#new"

  resources :quotes, only: [ :create, :show ]
  resources :leads, only: [ :index, :update ]
end
