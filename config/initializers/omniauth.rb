require "omniauth"
require "omniauth/rails_csrf_protection"
require "omniauth-google-oauth2"
require "omniauth-apple"

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.test_mode = Rails.env.test?

credentials = Rails.application.credentials
google_client_id = ENV["GOOGLE_CLIENT_ID"].presence || credentials.dig(:google, :client_id).presence
google_client_secret = ENV["GOOGLE_CLIENT_SECRET"].presence || credentials.dig(:google, :client_secret).presence
apple_client_id = ENV["APPLE_CLIENT_ID"].presence || credentials.dig(:apple, :client_id).presence
apple_team_id = ENV["APPLE_TEAM_ID"].presence || credentials.dig(:apple, :team_id).presence
apple_key_id = ENV["APPLE_KEY_ID"].presence || credentials.dig(:apple, :key_id).presence
apple_private_key = ENV["APPLE_PRIVATE_KEY"].presence || credentials.dig(:apple, :private_key).presence
apple_oauth_enabled = [ apple_client_id, apple_team_id, apple_key_id, apple_private_key ].all?(&:present?)

Rails.application.config.x.oauth.apple_enabled = apple_oauth_enabled
Rails.application.config.x.oauth.google_client_id = google_client_id

Rails.application.config.middleware.use OmniAuth::Builder do
  if google_client_id && google_client_secret
    provider :google_oauth2, google_client_id, google_client_secret,
             scope: "openid,email,profile", prompt: "select_account"
  end

  if apple_oauth_enabled
    provider :apple, apple_client_id, "",
             scope: "email name",
             team_id: apple_team_id,
             key_id: apple_key_id,
             pem: apple_private_key
  end
end
