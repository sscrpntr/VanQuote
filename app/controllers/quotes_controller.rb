class QuotesController < ApplicationController
  def new
    @quote = Quote.new
  end

  def create
    @quote = Quote.new(quote_params)

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

  def quote_params
    params.require(:quote).permit(
      :origin,
      :destination,
      :distance_km,
      :estimated_duration_minutes,
      :fuel_cost,
      :toll_cost,
      :vehicle_cost,
      :driver_cost,
      :loading_cost,
      :waiting_cost,
      :other_cost,
      :margin
    )
  end
end
