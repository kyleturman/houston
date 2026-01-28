# frozen_string_literal: true

# Request Spec Helper
# Provides convenient methods for testing API endpoints
#
# Usage:
#   RSpec.describe 'API Endpoint', type: :request do
#     it 'works with authentication' do
#       user = create(:user)
#       device = authenticated_device_for(user)
#       
#       get '/api/endpoint', headers: bearer_token_for(device)
#       expect(response).to have_http_status(:success)
#     end
#   end

module RequestSpecHelper
  # Create an authenticated device for the given user
  # Returns the device with @raw_token set
  def authenticated_device_for(user)
    create_authenticated_device(user)
  end

  # Get bearer token headers for the given device
  def bearer_token_for(device)
    { 'Authorization' => "Bearer #{device.instance_variable_get(:@raw_token)}" }
  end

  # Get user JWT headers for the given user
  def user_jwt_for(user)
    jwt_secret = ENV.fetch('USER_JWT_SECRET') { Rails.application.secret_key_base }
    payload = { 
      sub: user.id, 
      iat: Time.now.to_i, 
      exp: Time.now.to_i + 3600, 
      typ: 'user' 
    }
    token = JWT.encode(payload, jwt_secret, 'HS256')
    { 'Authorization' => "User #{token}" }
  end

  # Parse JSON response body
  def json_response
    JSON.parse(response.body)
  end

  # Get JSONAPI data from response
  def jsonapi_data
    json_response['data']
  end

  # Get JSONAPI attributes from response
  def jsonapi_attributes
    jsonapi_data['attributes']
  end

  # Get JSONAPI included from response
  def jsonapi_included
    json_response['included']
  end

  # Expect standard 401 unauthorized response
  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
  end

  # Expect standard 403 forbidden response
  def expect_forbidden
    expect(response).to have_http_status(:forbidden)
  end

  # Expect standard 404 not found response
  def expect_not_found
    expect(response).to have_http_status(:not_found)
  end

  # Expect standard 422 unprocessable entity response
  def expect_unprocessable
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

RSpec.configure do |config|
  config.include RequestSpecHelper, type: :request
end
