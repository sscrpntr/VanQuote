class LeadsController < ApplicationController
  def index
    @leads = Lead.includes(:quote).order(created_at: :desc)
  end

  def edit
    @lead = current_user_lead
  end

  def update
    @lead = current_user_lead

    @lead.update!(
      contact_preference: contact_preference_param,
      phone: phone_param
    )

    redirect_to quote_path(@lead.quote),
                notice: confirmation_message(@lead.contact_preference)
  end

  private

  def current_user_lead
    lead = Lead.find(params[:id])

    unless Current.user.admin? || lead.quote.user_id == Current.user.id
      raise ActiveRecord::RecordNotFound
    end

    lead
  end

  def contact_preference_param
    value = lead_params[:contact_preference]

    unless Lead::CONTACT_PREFERENCES.include?(value)
      raise ActionController::BadRequest,
            I18n.t("leads.errors.invalid_contact_preference")
    end

    value
  end

  def phone_param
    lead_params[:phone].to_s.strip.presence
  end

  def lead_params
    params.require(:lead).permit(
      :contact_preference,
      :phone
    )
  end

  def confirmation_message(preference)
    case preference
    when "EMAIL_QUOTE"
      I18n.t("leads.confirmations.email_quote")
    when "PHONE"
      I18n.t("leads.confirmations.phone")
    when "EMAIL_CONTACT"
      I18n.t("leads.confirmations.email_contact")
    end
  end
end
