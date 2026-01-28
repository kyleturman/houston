# frozen_string_literal: true

class PingController < ApplicationController
  include DeviceAuth

  before_action :authenticate_device!

  def show
    render json: {
      ok: true,
      device_id: current_device.id,
      device_name: current_device.name,
      time: Time.now.utc.iso8601
    }
  end
end
