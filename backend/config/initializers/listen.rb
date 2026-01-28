# Configure Listen gem for Docker file watching
# This prevents hanging when files change in development

if Rails.env.development?
  require 'listen'

  # Use polling mode in Docker (more reliable than native file system events)
  Listen::Adapter::Polling.class_eval do
    def self.usable?
      true
    end
  end

  # Configure Listen options
  Listen.logger = Rails.logger
  Listen.logger.level = Logger::WARN
end
