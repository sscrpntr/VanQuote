module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url(default_url:)
      return_to = session.delete(:return_to_after_authenticating)
      safe_return_to = url_from(return_to) if return_to.present?
      result = attach_public_quote_to_current_user
      return safe_return_to if safe_return_to

      unless result
        return default_url
      end

      quote = result[:quote]
      preference = result[:preference]

      if preference == "PHONE"
        return edit_lead_path(quote.lead)
      end

      public_quotes_path(
        token: quote.signed_id(
          purpose: :public_view,
          expires_in: 24.hours
        )
      )
    end

    def attach_public_quote_to_current_user
      token = session.delete(:quote_token_after_authenticating)
      preference = session.delete(:contact_preference_after_authenticating)

      return if token.blank? || Current.user.nil?

      preference =
        if Lead::CONTACT_PREFERENCES.include?(preference)
          preference
        end

      quote = Quote.find_signed!(
        token,
        purpose: :public_view
      )

      if quote.user_id.present? && quote.user_id != Current.user.id
        return nil
      end

      quote.update!(user: Current.user) if quote.user_id.blank?

      if preference.in?(%w[EMAIL_QUOTE EMAIL_CONTACT]) && quote.lead
        quote.lead.update!(
          contact_preference: preference
        )
      end

      {
        quote: quote,
        preference: preference
      }
    rescue ActiveSupport::MessageVerifier::InvalidSignature,
           ActiveRecord::RecordNotFound
      nil
    end

    def start_new_session_for(user)
      user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      ).tap do |session|
        Current.session = session

        cookies.signed.permanent[:session_id] = {
          value: session.id,
          httponly: true,
          same_site: :lax
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
