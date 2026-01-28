# frozen_string_literal: true

# Handles Plaid OAuth redirects for banks that require OAuth (like Chase)
# This is called after the user completes OAuth at their bank
#
# Flow:
# 1. User initiates Plaid Link in app
# 2. Plaid opens bank's OAuth page (e.g., Chase)
# 3. User authenticates at bank
# 4. Bank redirects to Plaid
# 5. Plaid redirects to our redirect_uri (/plaid-oauth) with oauth_state_id
# 6. We redirect to app deep link (heyhouston://plaid-oauth?oauth_state_id=...)
# 7. App receives deep link and calls handler.resumeAfterTermination(from: url)
# 8. Plaid Link resumes and completes the flow
#
class PlaidOauthController < ActionController::API
  # GET /plaid-oauth
  # Plaid redirects here after OAuth completion at the bank
  def callback
    # Plaid sends oauth_state_id as a query parameter
    oauth_state_id = params[:oauth_state_id]

    Rails.logger.info "[PlaidOAuth] Received callback with oauth_state_id: #{oauth_state_id}"

    if oauth_state_id.blank?
      Rails.logger.warn "[PlaidOAuth] Missing oauth_state_id in callback"
      # Still redirect to app - it will handle the error
      redirect_to "heyhouston://plaid-oauth?error=missing_oauth_state_id", allow_other_host: true
      return
    end

    # Redirect back to the iOS app with the oauth_state_id
    # The app will use this to resume the Plaid Link flow
    app_callback = "heyhouston://plaid-oauth?oauth_state_id=#{CGI.escape(oauth_state_id)}"

    Rails.logger.info "[PlaidOAuth] Redirecting to app: #{app_callback}"

    redirect_to app_callback, allow_other_host: true
  end
end
