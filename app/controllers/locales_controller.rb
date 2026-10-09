class LocalesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :set_locale

  FORM_DRAFT_FIELDS = {
    "registration" => {
      "user[first_name]" => 120,
      "user[last_name]" => 160,
      "user[email_address]" => 254,
      "user[accept_terms]" => :boolean,
      "user[accept_operational_email]" => :boolean
    },
    "session" => { "email_address" => 254 },
    "profile" => {
      "user[first_name]" => 120,
      "user[last_name]" => 160,
      "user[email_address]" => 254,
      "user[phone]" => 40
    },
    "quote" => { "quote[origin]" => 500, "quote[destination]" => 500, "email" => 254 },
    "lead" => { "lead[contact_preference]" => 32, "lead[phone]" => 40 },
    "quote_email_quote" => { "lead[contact_preference]" => 32 },
    "quote_phone" => { "lead[contact_preference]" => 32, "lead[phone]" => 40 },
    "quote_email_contact" => { "lead[contact_preference]" => 32 },
    "operational_consent" => { "accept_operational_email" => :boolean },
    "password_reset_request" => { "email_address" => 254 },
    "password_reset" => { "email_address" => 254 }
  }.freeze

  def update
    locale = params[:locale].to_s

    if available_locales.include?(locale)
      session[:locale] = locale
    end

    return_path = safe_redirect_path
    draft = sanitized_form_draft
    if draft
      session[:locale_form_draft] = {
        "form_key" => draft.fetch("form_key"),
        "values" => draft.fetch("values"),
        "return_to" => return_path,
        "expires_at" => 10.minutes.from_now.to_i
      }
    end

    redirect_to return_path
  end

  private

  def safe_redirect_path
    return_to = params[:return_to].to_s

    if return_to.start_with?("/") && !return_to.start_with?("//")
      return_to
    else
      root_path
    end
  end

  def sanitized_form_draft
    raw = params[:locale_form_draft].to_s
    return if raw.blank? || raw.bytesize > 12_000

    parsed = JSON.parse(raw)
    form_key = parsed["form_key"].to_s
    permitted_fields = FORM_DRAFT_FIELDS[form_key]
    values = parsed["values"]
    return unless permitted_fields && values.is_a?(Hash)

    sanitized = permitted_fields.each_with_object({}) do |(name, limit), result|
      next unless values.key?(name)

      value = values[name]
      if limit == :boolean
        result[name] = ActiveModel::Type::Boolean.new.cast(value)
      elsif value.is_a?(String)
        result[name] = value.truncate(limit)
      end
    end
    { "form_key" => form_key, "values" => sanitized }
  rescue JSON::ParserError
    nil
  end
end
