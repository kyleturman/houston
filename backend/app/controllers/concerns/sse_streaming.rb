# frozen_string_literal: true

# SSEStreaming - Shared concern for Server-Sent Events streaming
# Provides consistent SSE setup, formatting, and error handling across controllers
module SSEStreaming
  extend ActiveSupport::Concern

  included do
    include ActionController::Live
  end

  private

  # Set standard SSE headers for streaming responses
  def set_sse_headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
  end

  # Stream from a Redis channel with proper SSE formatting
  # Handles subscription, heartbeats, and cleanup
  #
  # @param channel [String] Redis pub/sub channel name
  # @param heartbeat_interval [Integer] Seconds between heartbeats (default: 30)
  # @yield [message] Optional block to process messages before sending
  def stream_from_channel(channel, heartbeat_interval: 30)
    set_sse_headers
    
    sub = nil
    begin
      sub = Streams::Broker.subscribe(channel)
      Rails.logger.info("[SSEStreaming] Subscribed to channel=#{channel}")
      
      loop do
        # Non-blocking check for messages with timeout
        message = nil
        begin
          message = Timeout.timeout(heartbeat_interval) { sub.queue.pop }
        rescue Timeout::Error
          # Send heartbeat comment to keep connection alive
          sse_write_comment('heartbeat')
          next
        end
        
        break unless message
        
        # Allow caller to process message if block given
        message = yield(message) if block_given?
        next unless message
        
        # Write SSE event
        sse_write_event(
          event: message[:event] || 'message',
          data: message[:data]
        )
      end
    rescue IOError, Errno::EPIPE
      # Client disconnected - normal termination
      Rails.logger.info("[SSEStreaming] Client disconnected from channel=#{channel}")
    rescue => e
      # Unexpected error
      Rails.logger.error("[SSEStreaming] Stream error on channel=#{channel}: #{e.class} - #{e.message}")
      sse_write_event(event: 'error', data: { message: 'Stream error occurred' })
    ensure
      Streams::Broker.unsubscribe(channel, sub) if sub
      response.stream.close
    end
  end

  # Write an SSE event with proper formatting
  # @param event [String, Symbol] Event type
  # @param data [Hash, String] Event data (will be JSON-encoded if Hash)
  def sse_write_event(event:, data:)
    response.stream.write("event: #{event}\n")
    data_string = data.is_a?(String) ? data : data.to_json
    response.stream.write("data: #{data_string}\n\n")
  end

  # Write an SSE comment (for heartbeats, debugging)
  # @param text [String] Comment text
  def sse_write_comment(text)
    response.stream.write(": #{text}\n\n")
  end
end
