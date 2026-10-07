class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :available_locales, :current_locale

  private

  def set_locale
    I18n.locale =
      session[:locale].presence_in(available_locales) ||
      I18n.default_locale
  end

  def available_locales
    %w[ca es en]
  end

  def current_locale
    I18n.locale.to_s
  end
end
