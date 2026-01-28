# frozen_string_literal: true

# Shared session-based authentication for admin controllers
module AdminSession
  extend ActiveSupport::Concern

  included do
    helper_method :current_user if respond_to?(:helper_method)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def admin_authenticated?
    session[:admin_authenticated] && current_user&.admin?
  end

  def sign_in_admin(user)
    session[:user_id] = user.id
    session[:admin_authenticated] = true
  end

  def sign_out_admin
    session.delete(:user_id)
    session.delete(:admin_authenticated)
  end
end
