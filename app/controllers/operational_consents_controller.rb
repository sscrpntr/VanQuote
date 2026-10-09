class OperationalConsentsController < ApplicationController
  def new
    redirect_to dashboard_path if Current.user.operational_email_consent_valid?
  end

  def create
    unless ActiveModel::Type::Boolean.new.cast(params[:accept_operational_email])
      flash.now[:alert] = I18n.t("operational_consent.required")
      render :new, status: :unprocessable_entity
      return
    end

    quote = pending_quote
    preference = session[:pending_operational_consent_preference]

    ActiveRecord::Base.transaction do
      unless Current.user.operational_email_consent_valid?
        Current.user.grant_operational_email_consent!(
          consent_text: I18n.t("registrations.new.operational_consent_text")
        )
      end

      if quote && Lead::CONTACT_PREFERENCES.include?(preference)
      phone = Current.user.phone
      lead_preference = preference == "PHONE" && phone.blank? ? nil : preference
      lead = quote.lead || quote.create_lead!(
        email: Current.user.email_address,
        phone: phone,
        consent_given: true,
        consent_at: Current.user.operational_email_consent_at,
        consent_basis: "account_operational_email",
        contact_preference: lead_preference,
        status: "NEW"
      )
      if quote.lead
        lead.update!(
          contact_preference: lead_preference,
          phone: phone,
          consent_given: true,
          consent_at: Current.user.operational_email_consent_at,
          consent_basis: "account_operational_email"
        )
      end
      end
    end

    session.delete(:pending_operational_consent_quote_id)
    session.delete(:pending_operational_consent_preference)

    if quote && Lead::CONTACT_PREFERENCES.include?(preference)
      if preference == "PHONE" && Current.user.phone.blank?
        session[:phone_contact_lead_id] = lead.id
        redirect_to edit_lead_path(lead)
      else
        session[:contact_confirmation_quote_id] = quote.id
        redirect_to contact_confirmation_path
      end
    elsif quote
      redirect_to quote_path(quote)
    else
      redirect_to dashboard_path
    end
  rescue ActiveRecord::RecordInvalid
    flash.now[:alert] = I18n.t("quotes.public.contact.request_failed")
    render :new, status: :unprocessable_entity
  end

  def destroy
    Current.user.withdraw_operational_email_consent!
    redirect_to profile_path, notice: I18n.t("operational_consent.withdrawn")
  end

  private

  def pending_quote
    id = session[:pending_operational_consent_quote_id]
    return if id.blank?

    Current.user.quotes.find_by(id: id)
  end
end
