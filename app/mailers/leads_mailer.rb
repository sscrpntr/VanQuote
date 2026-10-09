class LeadsMailer < ApplicationMailer
  def new_lead(lead)
    @lead = lead
    @quote = lead.quote
    mail subject: "New VanQuote lead", to: ENV.fetch("ADMIN_NOTIFICATION_EMAIL", "sergiescarpenter@gmail.com")
  end
end
