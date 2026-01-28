# frozen_string_literal: true

# StringIdAttributes
#
# A concern for ApplicationSerializer subclasses that need to convert integer ID
# attributes to strings in JSON responses.
#
# Why strings? JSON:API specification recommends string IDs because:
# - More flexible across different ID types (integers, UUIDs, composite keys)
# - Avoids JavaScript number precision issues (safe only up to 2^53-1)
# - Follows mobile client best practices
#
# Usage:
#   class NoteSerializer < ApplicationSerializer
#     include StringIdAttributes
#
#     string_id_attribute :goal_id
#   end
#
# This will automatically convert note.goal_id (integer) to a string in the JSON output.
module StringIdAttributes
  extend ActiveSupport::Concern

  class_methods do
    # Convert an integer ID attribute to string in serialized output
    #
    # @param attr_name [Symbol] The attribute name (e.g., :goal_id)
    def string_id_attribute(attr_name)
      attribute attr_name do |object|
        value = object.public_send(attr_name)
        value&.to_s
      end
    end
  end
end
