Rails.application.routes.draw do
  resource :session
  resources :passwords, only: [ :new, :create ]
  get "/passwords/reset", to: "passwords#reset_link", as: :new_password_reset
  post "/passwords/reset/verify", to: "passwords#verify_reset", as: :verify_password_reset
  get "/passwords/reset/edit", to: "passwords#edit_reset", as: :edit_password_reset
  patch "/passwords/reset/update", to: "passwords#update_reset", as: :update_password_reset
  resource :registration, only: [ :new, :create ]
  get "/email-verification", to: "email_verifications#show", as: :verify_email
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
