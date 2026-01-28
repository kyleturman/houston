# frozen_string_literal: true

# Streams::Broker - Redis-based pub/sub broker for SSE fanout across processes.
# Sidekiq workers publish events and Rails controllers subscribe to channels.
module Streams
  class Broker
    require 'json'
    require 'redis'
    require 'connection_pool'
    Subscriber = Struct.new(:id, :queue, :thread, :redis_conn)

    @mutex = Mutex.new
    @subs  = Hash.new { |h, k| h[k] = {} } # channel => { id => Subscriber }
    @seq   = 0
    @cleanup_thread = nil
    @publish_pool = nil

    class << self
      attr_reader :publish_pool

      # Lazy-initialize connection pool on first use
      def ensure_publish_pool!
        return @publish_pool if @publish_pool

        @publish_pool = ConnectionPool.new(size: 5, timeout: 5) do
          Redis.new(
            url: redis_url,
            connect_timeout: 2,
            read_timeout: 5,
            write_timeout: 2,
            reconnect_attempts: 3
          )
        end
      end
      def subscribe(channel)
        queue = Queue.new
        id = next_id
        # Use array as mutable container to share redis_conn between threads
        # Array element [0] will hold the Redis connection once the thread creates it
        redis_conn_holder = []

        th = Thread.new do
          begin
            # Dedicated Redis connection for subscription with timeout
            conn = Redis.new(
              url: redis_url,
              connect_timeout: 5,
              read_timeout: 30,
              write_timeout: 5,
              reconnect_attempts: 3
            )
            redis_conn_holder[0] = conn  # Store in shared container

            conn.subscribe(channel) do |on|
              Rails.logger.info("[Streams::Broker] subscribed channel=#{channel} sub_id=#{id}")
              on.message do |_chan, message|
                begin
                  parsed = JSON.parse(message)
                rescue JSON::ParserError
                  parsed = { 'event' => 'message', 'data' => { 'raw' => message } }
                end
                Rails.logger.debug("[Streams::Broker] recv channel=#{channel} event=#{parsed['event']}")

                # Push to in-memory queue; Ruby Queue#push has no timeout arg.
                # Apply simple backpressure: drop messages if queue is too large.
                if queue.length > 1000
                  Rails.logger.warn("[Streams::Broker] queue backlog >1000 for channel=#{channel} sub_id=#{id}, dropping message")
                else
                  queue.push(symbolize_keys(parsed))
                end
              end
            end
          rescue Redis::TimeoutError, Redis::ConnectionError => e
            Rails.logger.error("[Streams::Broker] Redis connection error for channel=#{channel} sub_id=#{id}: #{e.message}")
          rescue => e
            Rails.logger.error("[Streams::Broker] Subscription error for channel=#{channel} sub_id=#{id}: #{e.message}")
          ensure
            redis_conn_holder[0]&.disconnect!
          end
        end

        sub = Subscriber.new(id, queue, th, redis_conn_holder)
        @mutex.synchronize { @subs[channel][id] = sub }
        ensure_cleanup_thread
        sub
      end

      def unsubscribe(channel, subscriber)
        @mutex.synchronize do
          @subs[channel].delete(subscriber.id)
        end

        # Gracefully stop the subscriber thread and close Redis connection
        # IMPORTANT: Don't disconnect Redis while the subscription thread is still listening!
        # The thread will exit gracefully when we kill it, and the ensure block will disconnect.
        begin
          if subscriber.thread&.alive?
            Rails.logger.debug("[Streams::Broker] Stopping subscription thread #{subscriber.id}")

            # Kill the thread - this will trigger the ensure block in subscribe()
            # which properly disconnects Redis
            subscriber.thread.kill

            # Wait briefly for cleanup
            subscriber.thread.join(1)
          else
            # Thread already dead, manually cleanup Redis if needed
            redis_conn = subscriber.redis_conn.is_a?(Array) ? subscriber.redis_conn[0] : subscriber.redis_conn
            if redis_conn
              Rails.logger.debug("[Streams::Broker] Cleaning up stale Redis connection for subscriber #{subscriber.id}")
              redis_conn.disconnect! rescue nil
            end
          end
        rescue => e
          Rails.logger.error("[Streams::Broker] Error cleaning up subscriber #{subscriber.id}: #{e.message}")
        end
      end

      def publish(channel, event:, data: {})
        # Handle symbol event keys with convenience mapping
        event_string = case event
                       when :start then Streams::Channels::START
                       when :chunk then Streams::Channels::CHUNK
                       when :done  then Streams::Channels::DONE
                       when :message then 'message'
                       when :task_update then 'task_update'
                       else event.to_s
                       end

        payload = { event: event_string, data: deep_dup(data) }
        Rails.logger.debug("[Streams::Broker] publish channel=#{channel} event=#{payload[:event]}")

        begin
          # Use connection pool - borrows connection, publishes, returns to pool
          ensure_publish_pool!.with do |redis|
            redis.publish(channel, JSON.dump(payload))
          end
        rescue Redis::TimeoutError, Redis::ConnectionError => e
          Rails.logger.error("[Streams::Broker] Failed to publish to channel=#{channel}: #{e.message}")
        rescue ConnectionPool::TimeoutError => e
          Rails.logger.error("[Streams::Broker] Connection pool exhausted for channel=#{channel}: #{e.message}")
        end
      end

      # Clean up stale subscriptions periodically
      def cleanup_stale_subscriptions!
        @mutex.synchronize do
          @subs.each do |channel, subs|
            subs.each do |id, sub|
              unless sub.thread&.alive?
                Rails.logger.info("[Streams::Broker] Cleaning up stale subscription channel=#{channel} sub_id=#{id}")
                subs.delete(id)
                redis_conn = sub.redis_conn.is_a?(Array) ? sub.redis_conn[0] : sub.redis_conn
                redis_conn&.disconnect!
              end
            end
          end
        end
      end

      # Get connection statistics for monitoring
      def connection_stats
        @mutex.synchronize do
          active_count = 0
          stale_count = 0
          
          @subs.each do |_channel, subs|
            subs.each do |_id, sub|
              if sub.thread&.alive?
                active_count += 1
              else
                stale_count += 1
              end
            end
          end
          
          {
            active_subscriptions: active_count,
            total_channels: @subs.keys.count,
            stale_connections: stale_count,
            cleanup_thread_alive: @cleanup_thread&.alive? || false
          }
        end
      end

      private

      def next_id
        @seq += 1
      end
      
      def ensure_cleanup_thread
        return if @cleanup_thread&.alive?
        
        @cleanup_thread = Thread.new do
          loop do
            sleep 60 # Run cleanup every minute
            cleanup_stale_subscriptions!
          rescue => e
            Rails.logger.error("[Streams::Broker] Cleanup thread error: #{e.message}")
          end
        end
      end

      def deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        else
          obj
        end
      end

      def symbolize_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize_keys(v) }
        when Array
          obj.map { |v| symbolize_keys(v) }
        else
          obj
        end
      end

      def redis_url
        ENV['REDIS_URL'].presence || 'redis://redis:6379/0'
      end
    end
  end
end
