class AdminController < ApplicationController
  before_action :require_admin

  def index
    @total_leads = Lead.count
    @consented_leads = Lead.with_consent.includes(:quote).order(created_at: :desc)
    @total_requests = @consented_leads.count
  end

  private

  def require_admin
    head :forbidden unless Current.user&.admin?
  end
end
