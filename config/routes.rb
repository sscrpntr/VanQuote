Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]
  post "/registration/cancel-oauth", to: "oauth#cancel", as: :cancel_oauth_registration
  resource :operational_consent, only: [ :new, :create, :destroy ], controller: "operational_consents"
  get "/terms", to: "terms#show", as: :terms

  post "/auth/:provider", to: "oauth#unavailable", as: :oauth_initiation,
       constraints: { provider: /google_oauth2|apple/ }
  match "/auth/:provider/callback", to: "oauth#callback", via: [ :get, :post ],
       constraints: { provider: /google_oauth2|apple/ }
  match "/auth/failure", to: "oauth#failure", via: [ :get, :post ]

  root "quotes#new"

  get "/dashboard", to: "dashboards#show", as: :dashboard

  resource :profile, only: [ :show, :update ], controller: "profiles"

  post "locale", to: "locales#update"

  get "/quotes/contact-confirmation", to: "quotes#contact_confirmation", as: :contact_confirmation
  post "/quotes/public/contact", to: "quotes#request_contact", as: :request_quote_contact

  resources :quotes, only: [ :index, :new, :create, :show ] do
    get :public, on: :collection
  end

  resources :leads, only: [ :index, :edit, :update ]

  get "/admin", to: "admin#index", as: :admin
end
