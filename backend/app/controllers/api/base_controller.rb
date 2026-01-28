# frozen_string_literal: true

class Api::BaseController < ApplicationController
  include UserJwt
  include DeviceAuth

  before_action :authenticate_user!
end
