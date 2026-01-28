# frozen_string_literal: true

# Base serializer with standardized timestamp formatting
# All serializers should inherit from this to ensure consistent ISO8601 timestamps
class ApplicationSerializer
  include JSONAPI::Serializer

  # Helper method to format timestamps as ISO8601 for all serializers
  def self.iso8601_timestamp(attribute_name)
    attribute attribute_name do |object|
      object.public_send(attribute_name)&.iso8601
    end
  end
end
