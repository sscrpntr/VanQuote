class QuotesController < ApplicationController
  def new
    @quote = Quote.new
  end

  def create
    @quote = Quote.new(quote_params)
    apply_internal_defaults(@quote)

    if @quote.valid?
      calculator = QuoteCalculator.new(@quote)

      @quote.total_cost = calculator.total_cost
      @quote.recommended_price = calculator.recommended_price
      @quote.save!

      redirect_to quote_path(@quote)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @quote = Quote.find(params[:id])
    @calculator = QuoteCalculator.new(@quote)
  end

  private

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
      :destination,
      :distance_km,
      :estimated_duration_minutes
    )
  end
end
