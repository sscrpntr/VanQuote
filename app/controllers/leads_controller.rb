class LeadsController < ApplicationController
  def index
    @leads = Lead.includes(:quote).order(created_at: :desc)
  end
end
