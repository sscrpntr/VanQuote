class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    remember_public_quote_context
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new
    prepare_acceptance_form(oauth_signup)
  end

  def create
    submitted_user = params.require(:user)
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new(user_params)
    prepare_acceptance_form(oauth_signup)
    accepted_terms = @show_terms_checkbox && ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_terms])
    accepted_communications = @show_operational_checkbox && ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_operational_email])
    @user.valid?
    @user.errors.add(:base, I18n.t("registrations.new.terms_required")) if @terms_required && !accepted_terms
    @user.errors.add(:base, I18n.t("registrations.new.operational_consent_required")) if @operational_consent_required && !accepted_communications

    if @user.errors.empty?
      save_registration!(accepted_terms, accepted_communications, oauth_signup)
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

  def prepare_acceptance_form(oauth_signup)
    @existing_oauth_user = oauth_signup&.key?("user_id") && oauth_signup["user_id"].present? && @user.persisted?
    @terms_required = !@user.terms_accepted?
    @show_terms_checkbox = @terms_required
    @operational_consent_required = false
    @show_operational_checkbox = !@existing_oauth_user ||
      (pending_quote_contact_request? && !@user.operational_email_consent_valid?)
    @registration_submit_label = @existing_oauth_user ? t("registrations.new.accept") : t("registrations.new.submit")
  end

  def pending_quote_contact_request?
    token = session[:quote_token_after_authenticating]
    preference = session[:contact_preference_after_authenticating]
    return false unless token.present? && Lead::CONTACT_PREFERENCES.include?(preference)

    quote = Quote.find_signed(token, purpose: :public_view)
    return false if quote.user_id.present? && quote.user_id != @user.id
    return false if quote.user_id.blank? && quote.contact_email.present? &&
      !quote.contact_email.casecmp?(@user.email_address)

    true
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    false
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

  def save_registration!(accepted_terms, accepted_communications, oauth_signup)
    now = Time.current
    User.transaction do
      if accepted_terms
        @user.terms_accepted_at = now
        @user.terms_version = User::TERMS_VERSION
      end
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
