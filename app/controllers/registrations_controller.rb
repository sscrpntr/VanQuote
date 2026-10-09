class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    remember_public_quote_context
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new
  end

  def create
    submitted_user = params.require(:user)
    accepted_terms = ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_terms])
    accepted_communications = ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_operational_email])
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new(user_params)
    @user.valid?
    @user.errors.add(:base, I18n.t("registrations.new.terms_required")) unless accepted_terms

    if @user.errors.empty?
      save_registration!(accepted_communications, oauth_signup)
      session.delete(:pending_oauth_signup)
      start_new_session_for(@user)
      redirect_to after_authentication_url(default_url: dashboard_url)
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record
    @oauth_pending = pending_oauth_signup.present?
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @user ||= User.new(user_params)
    @oauth_pending = pending_oauth_signup.present?
    @user.errors.add(:base, I18n.t("registrations.new.errors.title"))
    render :new, status: :unprocessable_entity
  end

  private

  def pending_oauth_signup
    data = session[:pending_oauth_signup]
    return unless data.is_a?(Hash) && data["provider"].present? && data["uid"].present?

    data
  end

  def oauth_user_for(oauth_signup)
    user = oauth_signup["user_id"].present? ? User.find_by(id: oauth_signup["user_id"]) : nil
    user ||= User.new(
      first_name: oauth_signup["first_name"],
      last_name: oauth_signup["last_name"],
      email_address: oauth_signup["email_address"],
      password: SecureRandom.urlsafe_base64(32)
    )
  end

  def save_registration!(accepted_communications, oauth_signup)
    now = Time.current
    User.transaction do
      @user.terms_accepted_at = now
      @user.terms_version = User::TERMS_VERSION
      @user.save!

      if accepted_communications && !@user.operational_email_consent_valid?
        @user.grant_operational_email_consent!(
          consent_text: I18n.t("registrations.new.operational_consent_text")
        )
      end

      if oauth_signup
        existing_identity = Identity.find_by(provider: oauth_signup["provider"], uid: oauth_signup["uid"])
        raise ActiveRecord::RecordInvalid, @user if existing_identity && existing_identity.user_id != @user.id

        @user.identities.find_or_create_by!(provider: oauth_signup["provider"], uid: oauth_signup["uid"])
      end
    end
  end

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
      :first_name,
      :last_name,
      :email_address,
      :password,
      :password_confirmation
    )
  end
end
