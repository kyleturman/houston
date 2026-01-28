# frozen_string_literal: true

module Admin
  class SigninController < ActionController::Base
    include ActionController::Cookies
    include ActionController::Flash
    include AdminSession
    include JwtAuth
    include MagicLinkSender
    include InviteTokenAuth

    layout 'admin'

    # GET /admin/signin
    def new
      # If already authenticated, redirect to dashboard
      redirect_to admin_dashboard_path and return if admin_authenticated?
    end

    # POST /admin/signin
    def create
      if params[:auth_method] == 'invite_code'
        authenticate_with_invite_code
      else
        authenticate_with_magic_link
      end
    end

    # DELETE /admin/signout
    def destroy
      sign_out_admin
      flash[:success] = "Signed out successfully"
      redirect_to admin_signin_path
    end

    private

    def authenticate_with_magic_link
      email = params[:email]&.strip&.downcase

      if email.blank?
        flash[:error] = "Please enter an email address"
        redirect_to admin_signin_path and return
      end

      user = User.find_by(email: email)

      unless user&.admin?
        flash[:error] = "No admin account found with that email"
        redirect_to admin_signin_path and return
      end

      # Send magic link with admin context
      if send_magic_link(user, context: 'admin')
        flash[:success] = "Check your email for the sign-in link"
        redirect_to admin_signin_path
      else
        flash[:error] = "Failed to send magic link. Please try again."
        redirect_to admin_signin_path
      end
    end

    def authenticate_with_invite_code
      user, result = authenticate_admin_invite_token(
        email: params[:email],
        token: params[:invite_code]
      )

      unless user
        flash[:error] = result
        redirect_to admin_signin_path and return
      end

      sign_in_admin(user)
      flash[:success] = "Welcome, #{user.email}!"
      redirect_to admin_dashboard_path
    end
  end
end
