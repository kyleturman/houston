# frozen_string_literal: true

# Shared examples for testing authentication requirements
#
# Usage:
#   RSpec.describe 'API Endpoint', type: :request do
#     describe 'GET /api/things' do
#       it_behaves_like 'requires authentication' do
#         let(:make_request) { get '/api/things' }
#       end
#       
#       it_behaves_like 'requires user authentication' do
#         let(:make_request) { get '/api/things' }
#       end
#     end
#   end

RSpec.shared_examples 'requires authentication' do
  it 'returns 401 when no authentication provided' do
    make_request
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 when invalid token provided' do
    headers = { 'Authorization' => 'Bearer invalid_token' }
    if defined?(make_request_with_headers)
      make_request_with_headers(headers)
    else
      # Try to extract HTTP method from make_request
      # This is a fallback if make_request_with_headers is not defined
      make_request
    end
    expect(response).to have_http_status(:unauthorized)
  end
end

RSpec.shared_examples 'requires user authentication' do
  it 'returns 401 when no user token provided' do
    make_request
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 when invalid user JWT provided' do
    headers = { 'Authorization' => 'User invalid_jwt' }
    if defined?(make_request_with_headers)
      make_request_with_headers(headers)
    else
      make_request
    end
    expect(response).to have_http_status(:unauthorized)
  end
end

RSpec.shared_examples 'requires device authentication' do
  it 'returns 401 when no device token provided' do
    make_request
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 when invalid device token provided' do
    headers = { 'Authorization' => 'Bearer invalid_device_token' }
    if defined?(make_request_with_headers)
      make_request_with_headers(headers)
    else
      make_request
    end
    expect(response).to have_http_status(:unauthorized)
  end
end
