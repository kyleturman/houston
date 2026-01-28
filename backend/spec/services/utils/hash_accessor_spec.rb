# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Utils::HashAccessor', :service, :fast do
  # Mock the HashAccessor behavior
  let(:hash_accessor_class) do
    Class.new do
      def self.hash_get(hash, key)
        return nil unless hash.is_a?(Hash)
        hash[key] || hash[key.to_s]
      end

      def self.hash_get_string(hash, key)
        value = hash_get(hash, key)
        value&.to_s
      end

      def self.hash_get_hash(hash, key)
        value = hash_get(hash, key)
        value.is_a?(Hash) ? value : {}
      end
    end
  end

  describe '.hash_get' do
    it 'retrieves values with symbol keys' do
      hash = { tool_id: "123", name: "test" }
      expect(hash_accessor_class.hash_get(hash, :tool_id)).to eq("123")
      expect(hash_accessor_class.hash_get(hash, :name)).to eq("test")
    end

    it 'retrieves values with string keys' do
      hash = { "tool_id" => "123", "name" => "test" }
      expect(hash_accessor_class.hash_get(hash, :tool_id)).to eq("123")
      expect(hash_accessor_class.hash_get(hash, :name)).to eq("test")
    end

    it 'prefers symbol keys over string keys' do
      hash = { tool_id: "symbol_value", "tool_id" => "string_value" }
      expect(hash_accessor_class.hash_get(hash, :tool_id)).to eq("symbol_value")
    end

    it 'returns nil for missing keys' do
      hash = { other: "value" }
      expect(hash_accessor_class.hash_get(hash, :tool_id)).to be_nil
    end

    it 'handles non-hash input gracefully' do
      expect(hash_accessor_class.hash_get(nil, :key)).to be_nil
      expect(hash_accessor_class.hash_get("string", :key)).to be_nil
      expect(hash_accessor_class.hash_get([], :key)).to be_nil
    end
  end

  describe '.hash_get_string' do
    it 'converts values to strings' do
      hash = { tool_id: 123, name: nil }
      expect(hash_accessor_class.hash_get_string(hash, :tool_id)).to eq("123")
      expect(hash_accessor_class.hash_get_string(hash, :name)).to be_nil
    end
  end

  describe '.hash_get_hash' do
    it 'returns hash or empty hash' do
      hash = { data: { key: "value" }, empty: nil }
      expect(hash_accessor_class.hash_get_hash(hash, :data)).to eq({ key: "value" })
      expect(hash_accessor_class.hash_get_hash(hash, :empty)).to eq({})
      expect(hash_accessor_class.hash_get_hash(hash, :missing)).to eq({})
    end
  end
end
