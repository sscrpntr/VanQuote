class RegistrationsController < ApplicationController
  REQUIRED_ACCEPTANCE_COLUMNS = %w[
    terms_accepted_at terms_version operational_email_consent
    operational_email_consent_at operational_email_consent_text_version
    operational_email_consent_purpose
  ].freeze

  allow_unauthenticated_access

  def new
    remember_public_quote_context
    refresh_acceptance_schema
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new
    prepare_acceptance_form(oauth_signup)
    log_acceptance_schema_unavailable unless @acceptance_schema_available
  end

  def create
    submitted_user = params.require(:user)
    refresh_acceptance_schema
    oauth_signup = pending_oauth_signup
    @oauth_pending = oauth_signup.present?
    @user = oauth_signup ? oauth_user_for(oauth_signup) : User.new(user_params)
    prepare_acceptance_form(oauth_signup)

    unless @acceptance_schema_available
      log_acceptance_schema_unavailable
      return render :new, status: :service_unavailable
    end

    accepted_terms = @show_terms_checkbox && ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_terms])
    accepted_communications = @show_operational_checkbox && ActiveModel::Type::Boolean.new.cast(submitted_user[:accept_operational_email])
    @user.valid?
    @user.errors.add(:base, I18n.t("registrations.new.terms_required")) if @terms_required && !accepted_terms
    @user.errors.add(:base, I18n.t("registrations.new.operational_consent_required")) if @operational_consent_required && !accepted_communications

    if @user.errors.empty?
      save_registration!(accepted_terms, accepted_communications, oauth_signup)
      session.delete(:pending_oauth_signup)
      if oauth_signup
        start_new_session_for(@user)
        redirect_to after_authentication_url(default_url: dashboard_url)
      else
        begin
          VerificationMailer.verify(@user).deliver_now
          redirect_to new_session_path, notice: I18n.t("registrations.new.verify_email")
        rescue StandardError => error
          Rails.logger.error("Email verification delivery failed (#{error.class})")
          redirect_to new_session_path, alert: I18n.t("sessions.alerts.verification_delivery_failed")
        end
      end
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record
    @oauth_pending = pending_oauth_signup.present?
    @user.errors.add(:base, I18n.t("registrations.new.errors.save_failed")) if @user.errors.empty?
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @user ||= User.new(user_params)
    @oauth_pending = pending_oauth_signup.present?
    @user.errors.add(:base, I18n.t("registrations.new.errors.save_failed"))
    render :new, status: :unprocessable_entity
  end

  private

  def pending_oauth_signup
    data = session[:pending_oauth_signup]
    return unless data.is_a?(Hash) && data["provider"].present? && data["uid"].present?

    data
  end

  def prepare_acceptance_form(oauth_signup)
    @acceptance_schema_available = acceptance_schema_available?
    @existing_oauth_user = oauth_signup&.key?("user_id") && oauth_signup["user_id"].present? && @user.persisted?
    @terms_required = !@acceptance_schema_available || !@user.terms_accepted?
    @show_terms_checkbox = @terms_required
    @operational_consent_required = false
    @show_operational_checkbox = if !@existing_oauth_user
      true
    elsif @acceptance_schema_available
      pending_quote_contact_request? && !@user.operational_email_consent_valid?
    else
      false
    end
    @registration_submit_label = @existing_oauth_user ? t("registrations.new.accept") : t("registrations.new.submit")
  end

  def acceptance_schema_available?
    return false unless (REQUIRED_ACCEPTANCE_COLUMNS - User.column_names).empty?
    return false unless REQUIRED_ACCEPTANCE_COLUMNS.all? do |column|
      @user.has_attribute?(column) && @user.respond_to?("#{column}=")
    end

    OperationalEmailConsentEvent.table_exists?
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    false
  end

  def refresh_acceptance_schema
    columns_stale = (REQUIRED_ACCEPTANCE_COLUMNS - User.column_names).any?
    writers_stale = REQUIRED_ACCEPTANCE_COLUMNS.any? { |column| !User.method_defined?("#{column}=") }
    return unless columns_stale || writers_stale

    # A running development server can keep the pre-migration model schema cached.
    User.reset_column_information
    OperationalEmailConsentEvent.reset_column_information
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => error
    Rails.logger.error("Registration acceptance schema refresh failed (#{error.class})")
  end

  def log_acceptance_schema_unavailable
    Rails.logger.error("Registration blocked: acceptance schema is unavailable")
  end

  def pending_quote_contact_request?
    token = session[:quote_token_after_authenticating]
    preference = session[:contact_preference_after_authenticating]
    return false unless token.present? && Lead::CONTACT_PREFERENCES.include?(preference)

    quote = Quote.find_signed(token, purpose: :public_view)
    return quote.user_id == @user.id if quote.user_id.present?

    anonymous_quote_claim_authorized?(quote)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    false
  end

  def oauth_user_for(oauth_signup)
    user = oauth_signup["user_id"].present? ? User.find_by(id: oauth_signup["user_id"]) : nil
    if user
      # Older accounts received blank defaults when profile fields were added.
      # The OAuth form hides those fields, so use the verified provider profile
      # to fill only missing values before the explicit acceptance is saved.
      user.first_name = oauth_signup["first_name"] if user.first_name.blank?
      user.last_name = oauth_signup["last_name"] if user.last_name.blank?
      return user
    end

    User.new(
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

      @user.verify_email! if oauth_signup

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
