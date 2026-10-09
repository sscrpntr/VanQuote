class LeadsController < ApplicationController
  def index
    leads = Current.user.admin? ? Lead.all : Lead.joins(:quote).where(quotes: { user_id: Current.user.id })
    @leads = leads.includes(:quote).order(created_at: :desc)
  end

  def edit
    @lead = current_user_lead
    @phone_preference_locked = phone_preference_locked?
  end

  def update
    @lead = current_user_lead
    phone_preference_locked = phone_preference_locked?
    @phone_preference_locked = phone_preference_locked
    selected_preference = phone_preference_locked ? "PHONE" : contact_preference_param

    if @lead.consent_basis == "account_operational_email" &&
        (@lead.consent_withdrawn_at.present? || !Current.user.operational_email_consent_valid?)
      session[:pending_operational_consent_quote_id] = @lead.quote_id
      session[:pending_operational_consent_preference] = selected_preference
      redirect_to new_operational_consent_path
      return
    end

    @lead.assign_attributes(
      contact_preference: selected_preference,
      phone: phone_param
    )
    phone_selected = @lead.contact_preference == "PHONE"

    if @lead.valid?
      ActiveRecord::Base.transaction do
        Current.user.update!(phone: @lead.phone) if phone_selected
        @lead.save!
      end
      session.delete(:phone_contact_lead_id) if phone_preference_locked

      redirect_to quote_path(@lead.quote),
                  notice: confirmation_message(@lead.contact_preference)
    else
      render :edit, status: :unprocessable_entity
    end
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
    permitted_attributes = [ :phone ]
    permitted_attributes.unshift(:contact_preference) unless phone_preference_locked?

    params.require(:lead).permit(*permitted_attributes)
  end

  def phone_preference_locked?
    @lead && (
      @lead.contact_preference == "PHONE" ||
        session[:phone_contact_lead_id].to_s == @lead.id.to_s
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
