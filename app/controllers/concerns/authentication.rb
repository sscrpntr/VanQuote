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
      if resume_session && Current.user&.email_verified?
        true
      else
        terminate_session if Current.session
        request_authentication
      end
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
      return default_url if result&.dig(:invalid)
      return public_quotes_path(token: public_quote_token(result[:quote])) if result
      return safe_return_to if safe_return_to

      default_url
    end

    def attach_public_quote_to_current_user
      token = session[:quote_token_after_authenticating]
      return if token.blank? || Current.user.nil?

      quote = Quote.find_signed!(
        token,
        purpose: :public_view
      )

      session.delete(:quote_token_after_authenticating)
      session.delete(:contact_preference_after_authenticating)
      claim_result = claim_anonymous_quote(quote)
      if claim_result == :claimed
        flash[:notice] = I18n.t("quotes.public.contact.owner_updated", email: Current.user.email_address)
      elsif claim_result == :unauthorized || claim_result == :owned_by_another
        flash[:alert] = I18n.t("quotes.public.contact.account_mismatch")
      end
      { quote: quote, claimed: claim_result == :claimed }
    rescue ActiveSupport::MessageVerifier::InvalidSignature,
           ActiveRecord::RecordNotFound
      session.delete(:quote_token_after_authenticating)
      session.delete(:contact_preference_after_authenticating)
      flash[:alert] = I18n.t("quotes.public.contact.expired")
      { invalid: true }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid,
           ActiveRecord::ConnectionNotEstablished => error
      Rails.logger.error("Anonymous quote claim failed (#{error.class})")
      flash[:alert] = I18n.t("quotes.public.contact.request_failed")
      quote ? { quote: quote } : { invalid: true }
    end

    def public_quote_token(quote)
      quote.signed_id(purpose: :public_view, expires_in: 24.hours)
    end

    # Rails' encrypted cookie session records which anonymous quotes this
    # browser created. A public_view link alone never grants claim authority.
    def authorize_anonymous_quote_claim(quote)
      return if quote.user_id.present?

      ids = Array(session[:anonymous_quote_claim_quote_ids]).map(&:to_s)
      ids << quote.id.to_s
      session[:anonymous_quote_claim_quote_ids] = ids.uniq.last(10)
    end

    def anonymous_quote_claim_authorized?(quote)
      Array(session[:anonymous_quote_claim_quote_ids]).include?(quote.id.to_s)
    end

    def claim_anonymous_quote(quote)
      return :unauthorized unless Current.user

      claim_result = quote.with_lock do
        quote.reload
        if quote.user_id.present?
          quote.user_id == Current.user.id ? :already_owned : :owned_by_another
        elsif anonymous_quote_claim_authorized?(quote)
          quote.update!(user: Current.user)
          :claimed
        else
          :unauthorized
        end
      end

      if %i[claimed already_owned].include?(claim_result)
        ids = Array(session[:anonymous_quote_claim_quote_ids]).map(&:to_s)
        session[:anonymous_quote_claim_quote_ids] = ids - [ quote.id.to_s ]
      end
      claim_result
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
          same_site: :lax,
          secure: Rails.env.production?
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
