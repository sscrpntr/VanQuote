class QuoteMailer < ApplicationMailer
  def result(quote)
    @quote = quote
    @calculator = QuoteCalculator.new(quote)
    mail subject: "Your VanQuote transport estimate", to: quote.contact_email
  end
end
