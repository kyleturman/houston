import Foundation
import SwiftUI

/// Utilities for handling Markdown text in previews and displays
enum MarkdownUtils {
    
    /// Converts Markdown text to plain text suitable for previews
    /// - Uses AttributedString to properly parse Markdown
    /// - Removes all formatting (bold, italic, links, etc.)
    /// - Replaces newlines with spaces for inline display
    /// - Collapses multiple spaces into single spaces
    ///
    /// Example:
    /// ```
    /// let markdown = "# Title\n\nThis is **bold** text with a [link](url)."
    /// let plain = MarkdownUtils.toPlainText(markdown)
    /// // Result: "Title This is bold text with a link."
    /// ```
    static func toPlainText(_ markdown: String) -> String {
        // Replace newlines with spaces BEFORE parsing, so markdown parsing
        // doesn't strip them without leaving separators between content
        let preprocessed = markdown.replacingOccurrences(of: "\n", with: " ")

        // Use AttributedString to parse Markdown properly
        guard let attributed = try? AttributedString(markdown: preprocessed) else {
            // Fallback: if parsing fails, just clean up the raw text
            return cleanupRawText(markdown)
        }

        // Extract plain text from attributed string
        var plainText = String(attributed.characters)
        
        // Collapse multiple spaces into single space
        plainText = plainText.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        // Trim leading/trailing whitespace
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return plainText
    }
    
    /// Fallback for when Markdown parsing fails
    /// Just does basic cleanup of raw text
    private static func cleanupRawText(_ text: String) -> String {
        var cleaned = text
        
        // Replace newlines with spaces
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        
        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        // Trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}
