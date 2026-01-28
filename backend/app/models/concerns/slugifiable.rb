# frozen_string_literal: true

# Shared slug normalization for MCP server names.
# Converts names to lowercase, URL-safe identifiers.
# Example: "Last.fm" -> "lastfm", "My Cool Server!" -> "my-cool-server"
module Slugifiable
  extend ActiveSupport::Concern

  included do
    before_validation :slugify_name, if: -> { respond_to?(:name) && name.present? }
  end

  class_methods do
    # Class-level slugification for use without an instance
    # @param name [String] The name to slugify
    # @return [String] URL-safe slug
    def slugify(name)
      name.to_s
          .strip
          .downcase
          .gsub(/[^a-z0-9\s\-]/, '')  # Remove special characters except spaces and hyphens
          .gsub(/\s+/, '-')            # Replace spaces with hyphens
          .gsub(/-+/, '-')             # Collapse multiple hyphens
          .gsub(/^-|-$/, '')           # Remove leading/trailing hyphens
    end
  end

  private

  def slugify_name
    self.name = self.class.slugify(name)
  end
end
