# frozen_string_literal: true
require 'cgi'

class MagicLinkMailer < ApplicationMailer
  before_action :set_common_variables

  # iOS app signin - includes deep link for app to handle
  def app_signin
    @deep_link = build_app_deep_link
    mail(to: @user.email, subject: "Sign in to #{@server_name}")
  end

  # Admin dashboard signin - web-based, no deep link needed
  def admin_signin
    mail(to: @user.email, subject: "Sign in to #{@server_name} Admin Dashboard")
  end

  private

  def set_common_variables
    @user = params.fetch(:user)
    @server_url = params.fetch(:server_url)
    @server_name = params.fetch(:server_name)
    @token = params.fetch(:token)
  end

  def build_app_deep_link
    scheme = ENV["APP_URL_SCHEME"].presence || "heyhouston"
    "#{scheme}://signin?name=#{CGI.escape(@server_name)}&token=#{CGI.escape(@token)}&url=#{CGI.escape(@server_url)}&email=#{CGI.escape(@user.email)}"
  end
end
