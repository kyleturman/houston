# frozen_string_literal: true

# Shared contexts for authentication in request specs
# 
# Usage:
#   RSpec.describe 'Some API', type: :request do
#     include_context 'authenticated user'
#     
#     it 'works' do
#       get '/api/something', headers: auth_headers
#       expect(response).to have_http_status(:success)
#     end
#   end

RSpec.shared_context 'authenticated user' do
  let(:user) { create(:user) }
  let(:device) { create_authenticated_device(user) }
  let(:auth_headers) { auth_headers_for(device) }
end

RSpec.shared_context 'authenticated user with goal' do
  include_context 'authenticated user'
  
  let(:goal) { Goal.create!(user: user, title: 'Test Goal', description: 'Test description', status: :waiting) }
end

# Configure RSpec to include auth context automatically in request specs if desired
RSpec.configure do |config|
  # Automatically include authentication helpers in request specs
  config.include AuthHelpers, type: :request
end
