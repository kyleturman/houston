# frozen_string_literal: true

require 'open3'
require 'json'
require 'securerandom'
require 'timeout'

module Mcp
  # Minimal JSON-RPC 2.0 client over stdio. Spawns a process and exchanges JSON over pipes.
  class StdioClient
    DEFAULT_START_TIMEOUT = 10 # seconds (increased for Docker cold starts)
    DEFAULT_CALL_TIMEOUT = 30 # seconds (increased for slow API responses)

    def initialize(command:, env: {}, start_timeout: DEFAULT_START_TIMEOUT, call_timeout: DEFAULT_CALL_TIMEOUT)
      @command = Array(command)
      @env = (env || {}).transform_keys(&:to_s)
      @start_timeout = start_timeout
      @call_timeout = call_timeout
      @mutex = Mutex.new
      @started = false
      @id = 0
      @pending = {}
      start!
    end

    def call(method, params = {})
      retried = false
      begin
        ensure_started!
        req_id = next_id
        payload = { jsonrpc: '2.0', id: req_id, method: method, params: params }
        json = JSON.dump(payload)
        Timeout.timeout(@call_timeout) do
          @stdin.write(json + "\n")
          @stdin.flush
          loop do
            line = @stdout.gets
            raise ServerClosedError, "MCP stdio server closed" if line.nil?
            data = JSON.parse(line) rescue nil
            next unless data.is_a?(Hash) && (data['id'] == req_id)
            if data['error']
              raise "MCP RPC error: #{data['error'].inspect}"
            end
            return data['result']
          end
        end
      rescue ServerClosedError, Errno::EPIPE, IOError => e
        # Server died - try to restart once
        exit_status = @wait_thr&.value rescue nil
        Rails.logger.warn("[MCP::StdioClient] Server closed for #{@command.first}: #{e.message}, exit_status=#{exit_status&.exitstatus}")

        if !retried
          retried = true
          Rails.logger.info("[MCP::StdioClient] Attempting restart for #{@command.first}")
          restart!
          retry
        end
        raise "MCP stdio server closed (after restart attempt), exit_status=#{exit_status&.exitstatus}"
      end
    rescue Timeout::Error
      raise "MCP stdio call timeout for #{method}"
    end

    class ServerClosedError < StandardError; end

    def close
      @mutex.synchronize do
        cleanup_process
      end
    end

    def restart!
      @mutex.synchronize do
        cleanup_process
        do_start!
      end
    end

    private

    def cleanup_process
      begin
        @stdin&.close unless @stdin&.closed?
        @stdout&.close unless @stdout&.closed?
      rescue; end
      begin
        Process.kill('TERM', @pid) if @pid
      rescue; end
      @started = false
      @pid = nil
    end

    def start!
      return if @started
      do_start!
    end

    def do_start!
      Timeout.timeout(@start_timeout) do
        @stdin, @stdout, @wait_thr = Open3.popen2e(@env, *@command)
        @pid = @wait_thr.pid
        @started = true
      end
    rescue Timeout::Error
      raise "MCP stdio start timeout for #{@command.inspect}"
    end

    def ensure_started!
      start! unless @started
    end

    def next_id
      @mutex.synchronize { @id += 1 }
    end
  end
end
