class QuotesController < ApplicationController
  class_attribute :routes_service_class, default: GoogleRoutesService

  allow_unauthenticated_access only: %i[new create public contact_confirmation request_contact]
  before_action :resume_session, only: %i[new create public contact_confirmation request_contact]

  def index
    @quotes = Current.user.quotes.order(created_at: :desc)
  end

  def new
    @quote = Quote.new
  end

  def create
    @quote = Quote.new(quote_params)
    @quote.user = Current.user if Current.user
    @quote.contact_email = lead_email

    begin
      route = routes_service_class.new(
        origin: @quote.origin,
        destination: @quote.destination
      ).call

      @quote.distance_km = route[:distance_km]
      @quote.estimated_duration_minutes = route[:duration_minutes]
    rescue StandardError => e
      @quote.errors.add(
        :base,
        I18n.t("quotes.errors.route_calculation_failed")
      )

      Rails.logger.error("Google Routes error: #{e.message}")

      return render :new, status: :unprocessable_entity
    end

    apply_internal_defaults(@quote)

    if quote_input_valid?
      calculator = QuoteCalculator.new(@quote)

      @quote.total_cost = calculator.total_cost
      @quote.recommended_price = calculator.recommended_price

      @quote.save!

      redirect_to public_quotes_path(
        token: @quote.signed_id(
          purpose: :public_view,
          expires_in: 24.hours
        )
      )
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @quote = if Current.user.admin?
      Quote.find(params[:id])
    else
      Current.user.quotes.find(params[:id])
    end

    @calculator = QuoteCalculator.new(@quote)
  end

  def public
    @quote = Quote.find_signed!(
      params[:token],
      purpose: :public_view
    )
    @can_request_contact = quote_claimable_by?(@quote, Current.user)

    @calculator = QuoteCalculator.new(@quote)
  end

  def request_contact
    token = params[:token].to_s
    preference = params[:contact_preference].to_s
    quote = Quote.find_signed!(token, purpose: :public_view)

    unless Lead::CONTACT_PREFERENCES.include?(preference)
      flash[:alert] = I18n.t("quotes.public.contact.invalid_preference")
      redirect_to public_quotes_path(token: token)
      return
    end

    unless Current.user
      session[:quote_token_after_authenticating] = token
      session[:contact_preference_after_authenticating] = preference
      redirect_to new_session_path
      return
    end

    unless claim_quote_for_current_user(quote)
      flash[:alert] = I18n.t("quotes.public.contact.account_mismatch")
      redirect_to public_quotes_path(token: token)
      return
    end

    unless Current.user.operational_email_consent_valid?
      session[:pending_operational_consent_quote_id] = quote.id
      session[:pending_operational_consent_preference] = preference
      redirect_to new_operational_consent_path
      return
    end

    phone = preference == "PHONE" ? Current.user.phone : nil
    lead_preference = preference == "PHONE" && phone.blank? ? nil : preference
    lead = quote.lead || quote.create_lead!(
      email: Current.user.email_address,
      phone: phone,
      contact_preference: lead_preference,
      consent_given: true,
      consent_at: Current.user.operational_email_consent_at,
      consent_basis: "account_operational_email",
      status: "NEW"
    )
    if quote.lead
      lead.update!(
        email: Current.user.email_address,
        phone: phone,
        contact_preference: lead_preference,
        consent_given: true,
        consent_at: Current.user.operational_email_consent_at,
        consent_basis: "account_operational_email"
      )
    end

    if preference == "PHONE" && phone.blank?
      session[:phone_contact_lead_id] = lead.id
      redirect_to edit_lead_path(lead)
    else
      session[:contact_confirmation_quote_id] = quote.id
      redirect_to contact_confirmation_path
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveRecord::RecordNotFound
    flash[:alert] = I18n.t("quotes.public.contact.expired")
    redirect_to(Current.user ? dashboard_path : root_path)
  rescue ActiveRecord::RecordInvalid
    flash[:alert] = I18n.t("quotes.public.contact.request_failed")
    redirect_to public_quotes_path(token: token)
  end

  def contact_confirmation
    quote_id = session.delete(:contact_confirmation_quote_id)
    quote = Current.user&.quotes&.joins(:lead)&.find_by(id: quote_id)

    return if quote&.lead&.contact_preference.present?

    redirect_to(Current.user ? dashboard_path : root_path)
  end

  private

  def quote_input_valid?
    email = lead_email

    email.present? &&
      email.match?(URI::MailTo::EMAIL_REGEXP) &&
      @quote.valid?
  end

  def lead_email
    if Current.user
      Current.user.email_address
    else
      params[:email].to_s.strip
    end
  end

  def quote_claimable_by?(quote, user)
    return false unless user
    return quote.user_id == user.id if quote.user_id.present?

    quote.contact_email.present? && quote.contact_email.casecmp?(user.email_address)
  end

  def claim_quote_for_current_user(quote)
    quote.with_lock do
      quote.reload
      return quote.user_id == Current.user.id if quote.user_id.present?
      return false unless quote_claimable_by?(quote, Current.user)

      quote.update!(user: Current.user)
      true
    end
  end

  def apply_internal_defaults(quote)
    distance = quote.distance_km.to_d
    duration_hours = quote.estimated_duration_minutes.to_d / 60

    quote.fuel_cost = distance * 0.12
    quote.toll_cost = 0
    quote.vehicle_cost = distance * 0.10
    quote.driver_cost = duration_hours * 25
    quote.loading_cost = 20
    quote.waiting_cost = 0
    quote.other_cost = 10
    quote.margin = 25
  end

  def quote_params
    params.require(:quote).permit(
      :origin,
      :destination
    )
  end
end
