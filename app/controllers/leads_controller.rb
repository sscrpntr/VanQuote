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
      raise ActionController::BadRequest, "Invalid contact preference"
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
      "Te enviaremos el presupuesto por email."
    when "PHONE"
      "Perfecto. Nos pondremos en contacto contigo por teléfono."
    when "EMAIL_CONTACT"
      "Perfecto. Nos pondremos en contacto contigo por email."
    end
  end
end
