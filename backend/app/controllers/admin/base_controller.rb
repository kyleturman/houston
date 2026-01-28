# frozen_string_literal: true

module Admin
  class BaseController < ActionController::Base
    include ActionController::Cookies
    include ActionController::Flash
    include AdminSession

    before_action :require_admin

    private

    def require_admin
      redirect_to admin_signin_path unless admin_authenticated?
    end
  end
end
