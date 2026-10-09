class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale
  before_action :load_locale_form_draft

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :available_locales, :current_locale, :locale_form_value, :locale_form_checked?

  private

  def set_locale
    I18n.locale =
      session[:locale].presence_in(available_locales) ||
      :es
  end

  def available_locales
    %w[ca es en]
  end

  def current_locale
    I18n.locale.to_s
  end

  def load_locale_form_draft
    draft = session[:locale_form_draft]
    return unless draft.is_a?(Hash)

    if draft["expires_at"].to_i < Time.current.to_i
      session.delete(:locale_form_draft)
    elsif draft["return_to"] == request.fullpath
      @locale_form_draft = draft
      session.delete(:locale_form_draft)
    end
  end

  def locale_form_value(form_key, field_name, fallback = nil)
    fields = @locale_form_draft&.dig("form_key") == form_key ? @locale_form_draft["values"] : nil
    return fallback unless fields&.key?(field_name)

    fields[field_name]
  end

  def locale_form_checked?(form_key, field_name, fallback = false)
    value = locale_form_value(form_key, field_name, fallback)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
