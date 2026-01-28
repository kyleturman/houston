# frozen_string_literal: true

module Api
  # Returns server capabilities to iOS clients
  class CapabilitiesController < BaseController
    skip_before_action :authenticate_user!, only: [:index]

    # GET /api/capabilities
    # Public endpoint - no authentication required
    #
    # Returns:
    #   {
    #     "sse_enabled": true,
    #     "version": "1.0.0"
    #   }
    def index
      render json: {
        sse_enabled: true,
        version: '1.0.0'
      }
    end
  end
end
