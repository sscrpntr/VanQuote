class LocalesController < ApplicationController
  skip_before_action :set_locale

  def update
    locale = params[:locale].to_s

    if available_locales.include?(locale)
      session[:locale] = locale
    end

    redirect_to safe_redirect_path
  end

  private

  def safe_redirect_path
    return_to = params[:return_to].to_s

    if return_to.start_with?("/") && !return_to.start_with?("//")
      return_to
    else
      root_path
    end
  end
end
