class QuotesController < ApplicationController
  class_attribute :routes_service_class, default: GoogleRoutesService

  allow_unauthenticated_access only: %i[new create public contact_confirmation request_contact]
  before_action :resume_session, only: %i[new create public contact_confirmation request_contact]

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { render plain: I18n.t("quotes.errors.too_many_requests"), status: :too_many_requests }

  def index
    @quotes = Current.user.quotes.order(created_at: :desc)
  end

  def new
    @quote = Quote.new
    @idempotency_key = QuoteCreationRequest.generate_key
    session[:quote_creation_binding] ||= SecureRandom.urlsafe_base64(32)
  end

  def create
    @quote = Quote.new(quote_params)
    @quote.user = Current.user if Current.user
    @quote.contact_email = lead_email
    @idempotency_key = params[:idempotency_key].to_s
    session[:quote_creation_binding] ||= SecureRandom.urlsafe_base64(32)

    unless quote_request_input_valid?
      @idempotency_key = QuoteCreationRequest.generate_key unless QuoteCreationRequest.valid_key?(@idempotency_key)
      return render :new, status: :unprocessable_entity
    end

    unless QuoteCreationRequest.valid_key?(@idempotency_key)
      @quote.errors.add(:base, I18n.t("quotes.errors.idempotency_key_invalid"))
      @idempotency_key = QuoteCreationRequest.generate_key
      return render :new, status: :unprocessable_entity
    end

    request_digest = QuoteCreationRequest.request_digest(
      origin: @quote.origin,
      destination: @quote.destination,
      contact_email: @quote.contact_email
    )
    reservation = QuoteCreationRequest.claim!(
      key: @idempotency_key,
      request_digest: request_digest,
      user: Current.user,
      session_binding: session[:quote_creation_binding],
      http_request: request
    )

    if reservation[:status] == :completed
      @quote = reservation.fetch(:quote)
      return render_completed_quote
    end

    operation = reservation.fetch(:operation)
    claim_token = reservation.fetch(:claim_token)

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

      Rails.logger.error("Google Routes error (#{e.class})")

      operation.fail!(claim_token)
      return render :new, status: :unprocessable_entity
    end

    apply_internal_defaults(@quote)

    if quote_input_valid?
      calculator = QuoteCalculator.new(@quote)

      @quote.total_cost = calculator.total_cost
      @quote.recommended_price = calculator.recommended_price

      operation.complete!(claim_token) do
        @quote.save!
        @quote
      end
      authorize_anonymous_quote_claim(@quote) unless Current.user

      render_completed_quote
    else
      operation.fail!(claim_token)
      render :new, status: :unprocessable_entity
    end
  rescue QuoteCreationRequest::AnonymousLimitReached
    @quote.errors.add(:base, I18n.t("quotes.errors.anonymous_limit"))
    render :new, status: :too_many_requests
  rescue QuoteCreationRequest::RequestInProgress
    @quote.errors.add(:base, I18n.t("quotes.errors.quote_request_in_progress"))
    response.set_header("Retry-After", QuoteCreationRequest::LEASE_DURATION.to_i.to_s)
    render :new, status: :conflict
  rescue QuoteCreationRequest::KeyConflict
    @quote.errors.add(:base, I18n.t("quotes.errors.quote_request_conflict"))
    @idempotency_key = QuoteCreationRequest.generate_key
    render :new, status: :conflict
  rescue QuoteCreationRequest::LostClaim
    @quote.errors.add(:base, I18n.t("quotes.errors.quote_request_in_progress"))
    response.set_header("Retry-After", QuoteCreationRequest::LEASE_DURATION.to_i.to_s)
    render :new, status: :conflict
  rescue ActiveRecord::RecordInvalid
    operation&.fail!(claim_token) if operation && claim_token
    raise
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
    lead = quote.with_lock do
      quote.reload
      raise ActiveRecord::RecordNotFound unless quote.user_id == Current.user.id

      existing_lead = quote.lead
      attributes = {
        email: Current.user.email_address,
        phone: phone,
        contact_preference: lead_preference,
        consent_given: true,
        consent_at: Current.user.operational_email_consent_at,
        consent_basis: "account_operational_email"
      }
      if existing_lead
        existing_lead.update!(attributes)
        existing_lead
      else
        quote.create_lead!(attributes.merge(status: "NEW"))
      end
    end

    begin
      lead.notify_admin_once!
    rescue StandardError => error
      Rails.logger.error("Lead notification email failed (#{error.class})")
      flash[:alert] = I18n.t("quotes.public.contact.email_failed")
      redirect_to public_quotes_path(token: token)
      return
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

  def quote_request_input_valid?
    email = lead_email
    @quote.origin.present? && @quote.destination.present? &&
      email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def render_completed_quote
    authorize_anonymous_quote_claim(@quote) if @quote.user_id.nil?

    begin
      @quote.deliver_result_email_once!
    rescue StandardError => error
      Rails.logger.error("Quote email delivery failed (#{error.class})")
      flash[:alert] = I18n.t("quotes.errors.email_delivery_failed")
    end

    redirect_to public_quotes_path(
      token: @quote.signed_id(
        purpose: :public_view,
        expires_in: 24.hours
      )
    )
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

    anonymous_quote_claim_authorized?(quote)
  end

  def claim_quote_for_current_user(quote)
    result = claim_anonymous_quote(quote)
    flash[:notice] = I18n.t("quotes.public.contact.owner_updated", email: Current.user.email_address) if result == :claimed
    %i[claimed already_owned].include?(result)
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
