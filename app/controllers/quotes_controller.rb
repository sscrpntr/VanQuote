class QuotesController < ApplicationController
  class_attribute :routes_service_class, default: GoogleRoutesService

  allow_unauthenticated_access only: %i[new create public]

  def index
    @quotes = Current.user.quotes.order(created_at: :desc)
  end

  def new
    resume_session
    @quote = Quote.new
  end

  def create
    authenticated?
    @quote = Quote.new(quote_params)
    @quote.user = Current.user if Current.user

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

      Quote.transaction do
        @quote.save!

        @quote.create_lead!(
          email: lead_email,
          phone: lead_phone,
          consent_given: true,
          consent_at: Time.current,
          status: "NEW"
        )
      end

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

    @calculator = QuoteCalculator.new(@quote)
  end

  private

  def quote_input_valid?
    email = lead_email
    consent_given = ActiveModel::Type::Boolean.new.cast(params[:consent_given])

    email.present? &&
      email.match?(URI::MailTo::EMAIL_REGEXP) &&
      consent_given &&
      @quote.valid?
  end

  def lead_email
    if Current.user
      Current.user.email_address
    else
      params[:email].to_s.strip
    end
  end

  def lead_phone
    if Current.user
      Current.user.phone
    else
      params[:phone].to_s.strip
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
