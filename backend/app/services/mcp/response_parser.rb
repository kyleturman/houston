# frozen_string_literal: true

module Mcp
  # Shared response parser for MCP server responses.
  # Handles both SSE (Server-Sent Events) format and plain JSON.
  #
  # SSE format: "event: message\ndata: {...}\n\n"
  # Plain JSON: "{...}"
  module ResponseParser
    class ParseError < StandardError; end

    class << self
      # Parse an MCP response that may be SSE format or plain JSON
      # @param body [String] The response body
      # @param context [String] Optional context for error logging (e.g., "[MCP]", "[UrlServerService]")
      # @return [Hash, nil] Parsed JSON data or nil on parse failure
      def parse(body, context: "[MCP]")
        return nil if body.blank?

        body_str = body.to_s

        # SSE format: "event: message\ndata: {...}\n\n"
        if sse_format?(body_str)
          parse_sse(body_str, context: context)
        else
          parse_json(body_str, context: context)
        end
      end

      # Check if response is SSE format
      # @param body [String] The response body
      # @return [Boolean]
      def sse_format?(body)
        body.include?('event:') && body.include?('data:')
      end

      private

      def parse_sse(body, context:)
        data_line = body.lines.find { |l| l.start_with?('data:') }
        return nil unless data_line

        json_str = data_line.sub('data:', '').strip
        JSON.parse(json_str)
      rescue JSON::ParserError => e
        Rails.logger.warn("#{context} SSE JSON parse failed: #{e.message}")
        nil
      end

      def parse_json(body, context:)
        JSON.parse(body)
      rescue JSON::ParserError => e
        Rails.logger.warn("#{context} JSON parse failed: #{e.message}")
        nil
      end
    end
  end
end
