# frozen_string_literal: true

require 'webmock/rspec'

# Allow connections to localhost for any local testing services
WebMock.disable_net_connect!(allow_localhost: true)
