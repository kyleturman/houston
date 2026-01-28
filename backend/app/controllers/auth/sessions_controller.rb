# frozen_string_literal: true

class Auth::SessionsController < ApplicationController
  include DeviceAuth
  include UserJwt

  before_action :authenticate_device!

  # JWT logout is typically client-side; this is a no-op for parity
  def destroy
    head :no_content
  end
end
