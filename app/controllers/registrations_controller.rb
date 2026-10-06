class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    remember_public_quote_context
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      start_new_session_for(@user)
      redirect_to after_authentication_url
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def remember_public_quote_context
    if params[:quote_token].present?
      session[:quote_token_after_authenticating] = params[:quote_token]
    end

    if params[:contact_preference].present?
      session[:contact_preference_after_authenticating] =
        params[:contact_preference]
    end
  end

  def user_params
    params.require(:user).permit(
      :email_address,
      :password,
      :password_confirmation
    )
  end
end
