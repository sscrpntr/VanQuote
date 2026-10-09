Rails.application.config.session_store :cookie_store,
  key: "_van_quote_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax
