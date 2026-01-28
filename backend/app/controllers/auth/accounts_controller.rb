# frozen_string_literal: true

module Auth
  class AccountsController < ApplicationController
    # POST /api/auth/account_status
    # Params: { email: string }
    def status
      email = params.require(:email).to_s.strip.downcase
      user = User.find_by(email: email)
      exists = user.present?
      render json: { exists: exists }
    end
  end
end
