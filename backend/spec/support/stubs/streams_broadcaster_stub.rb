# frozen_string_literal: true

# Stub for Streams::Broadcaster until it's fully implemented
# This allows tests to run while the feature is being developed
module Streams
  module Broadcaster
    class << self
      def broadcast_resource_created(user:, resource:, channel:)
        # Stub implementation - will be replaced with real SSE broadcasting
        Rails.logger.debug("[Streams::Broadcaster STUB] broadcast_resource_created: resource=#{resource.class.name}:#{resource.id}")
        true
      end

      def broadcast_resource_updated(user:, resource:, channel:)
        Rails.logger.debug("[Streams::Broadcaster STUB] broadcast_resource_updated: resource=#{resource.class.name}:#{resource.id}")
        true
      end

      def broadcast_resource_destroyed(user:, resource:, channel:)
        Rails.logger.debug("[Streams::Broadcaster STUB] broadcast_resource_destroyed: resource=#{resource.class.name}:#{resource.id}")
        true
      end
    end
  end
end
