class LeadsController < ApplicationController
  def index
    @leads = Lead.includes(:quote).order(created_at: :desc)
  end

  def update
    @lead = Lead.find(params[:id])
    @lead.update!(contact_preference: contact_preference_param)

    redirect_to quote_path(@lead.quote), notice: confirmation_message(@lead.contact_preference)
  end

  private

  def contact_preference_param
    value = params.require(:lead).permit(:contact_preference)[:contact_preference]

    unless Lead::CONTACT_PREFERENCES.include?(value)
      raise ActionController::BadRequest, "Invalid contact preference"
    end

    value
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
