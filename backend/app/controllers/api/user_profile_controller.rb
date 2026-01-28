# frozen_string_literal: true

class Api::UserProfileController < Api::BaseController
  before_action :authenticate_user!

  # GET /api/user/profile
  def show
    render json: {
      email: current_user.email,
      name: current_user.name,
      onboarding_completed: current_user.onboarding_completed
    }
  end

  # PATCH /api/user/profile
  def update
    update_params = {}
    update_params[:name] = params[:name] if params[:name].present?
    update_params[:email] = params[:email] if params[:email].present?
    update_params[:onboarding_completed] = params[:onboarding_completed] if params.key?(:onboarding_completed)

    if current_user.update(update_params)
      render json: {
        email: current_user.email,
        name: current_user.name,
        onboarding_completed: current_user.onboarding_completed
      }
    else
      render json: { error: current_user.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end
end
