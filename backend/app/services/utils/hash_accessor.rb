# frozen_string_literal: true

module Utils
  # Utility methods for accessing hash keys that might be symbols or strings
  module HashAccessor
    module_function

    # Get value from hash using either symbol or string key
    # hash_get(data, :tool_id) will try data[:tool_id] then data['tool_id']
    def hash_get(hash, key)
      return nil unless hash.is_a?(Hash)
      
      # Try symbol key first, then string key
      hash[key] || hash[key.to_s]
    end

    # Get string value, converting to string if needed
    def hash_get_string(hash, key)
      value = hash_get(hash, key)
      value&.to_s
    end

    # Get hash value, returning nil if not found or not a hash
    # This allows || chaining to try multiple keys
    def hash_get_hash(hash, key)
      value = hash_get(hash, key)
      value.is_a?(Hash) ? value : nil
    end
  end
end
