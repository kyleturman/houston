# frozen_string_literal: true

# GlobalStreamController - SSE stream for global user events
# Broadcasts real-time updates for notes, tasks, goals created across all agentables
class Api::GlobalStreamController < Api::BaseController
  include SSEStreaming

  # GET /api/stream/global
  def stream
    # Set SSE headers before any streaming writes
    set_sse_headers

    channel = Streams::Channels.global_for_user(user: current_user)
    Rails.logger.info("[GlobalStreamController#stream] user=#{current_user.id} channel=#{channel} start")

    sub = nil
    stream_thread = nil

    begin
      # Set up subscription with timeout protection
      sub = Timeout.timeout(10) do
        Streams::Broker.subscribe(channel)
      end

      sse_write(event: Streams::Channels::WELCOME, data: { channel: channel })
      started_at = Time.now
      last_heartbeat_at = Time.now
      last_activity_at = Time.now
      heartbeat_every = 30 # seconds - send keepalive events (reduced from 20 to lower server load)
      max_duration = 600   # seconds; force reconnect periodically (10 min)
      max_idle_time = 300  # seconds; close if no activity for 5 minutes

      # Use a separate thread to handle the stream with timeout protection
      stream_thread = Thread.new do
        loop do
          break if response.stream.closed?

          # Check for timeouts
          now = Time.now
          if (now - started_at) >= max_duration
            Rails.logger.info("[GlobalStreamController#stream] user=#{current_user.id} max duration reached")
            break
          end

          if (now - last_activity_at) >= max_idle_time
            Rails.logger.info("[GlobalStreamController#stream] user=#{current_user.id} idle timeout")
            break
          end

          # Blocking pop with short timeout for responsive streaming
          # Using blocking pop avoids polling delays - messages are sent immediately when they arrive
          payload = nil
          begin
            Timeout.timeout(1.0) do
              payload = sub.queue.pop  # Blocking pop - wakes immediately when message arrives
            end
            last_activity_at = Time.now if payload
          rescue Timeout::Error
            # No message in 1 second - check timeouts and maybe send heartbeat
          end

          if payload
            event = Utils::HashAccessor.hash_get(payload, :event)
            data  = Utils::HashAccessor.hash_get_hash(payload, :data)
            Rails.logger.debug("[GlobalStreamController#stream] user=#{current_user.id} event=#{event}")

            begin
              sse_write(event: event, data: data)
            rescue ActionController::Live::ClientDisconnected, IOError => e
              Rails.logger.debug("[GlobalStreamController#stream] client disconnected during write: #{e.message}")
              break
            rescue => e
              Rails.logger.warn("[GlobalStreamController#stream] write error: #{e.message}")
              break
            end
          else
            # No message received in timeout period - send keepalive if needed
            now = Time.now
            if (now - last_heartbeat_at) >= heartbeat_every
              begin
                sse_write(event: 'keepalive', data: { timestamp: now.to_i })
                last_heartbeat_at = now
                Rails.logger.debug("[GlobalStreamController#stream] keepalive sent")
              rescue ActionController::Live::ClientDisconnected, IOError => e
                Rails.logger.debug("[GlobalStreamController#stream] client disconnected during keepalive")
                break
              rescue => e
                Rails.logger.warn("[GlobalStreamController#stream] keepalive failed: #{e.message}")
                break
              end
            end
            # No sleep needed - blocking pop handles the wait
          end
        end
      end

      # Wait for the stream thread with overall timeout
      stream_thread.join(max_duration + 10)

    rescue Timeout::Error => e
      Rails.logger.error("[GlobalStreamController#stream] timeout error: #{e.message}")
    rescue ActionController::Live::ClientDisconnected, IOError => e
      Rails.logger.info("[GlobalStreamController#stream] client disconnected: #{e.message}")
    rescue => e
      Rails.logger.error("[GlobalStreamController#stream] unexpected error: #{e.message}")
    ensure
      # Cleanup with timeout protection
      begin
        Timeout.timeout(5) do
          Rails.logger.info("[GlobalStreamController#stream] user=#{current_user.id} channel=#{channel} closed")

          # Kill stream thread if still alive
          if stream_thread&.alive?
            stream_thread.kill
            stream_thread.join(1)
          end

          # Unsubscribe from broker
          Streams::Broker.unsubscribe(channel, sub) if sub

          # Close response stream
          response.stream.close unless response.stream.closed?
        end
      rescue Timeout::Error
        Rails.logger.error("[GlobalStreamController#stream] cleanup timeout for user=#{current_user.id}")
        # Force cleanup
        stream_thread&.kill
        begin
          response.stream.close
        rescue
          # ignore
        end
      rescue => e
        Rails.logger.error("[GlobalStreamController#stream] cleanup error: #{e.message}")
      end
    end
  end

  private

  # Use sse_write_event from SSEStreaming concern
  alias_method :sse_write, :sse_write_event
end
