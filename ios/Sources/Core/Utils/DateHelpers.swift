import Foundation

/// Utility functions for date parsing and formatting
///
/// Provides consistent date handling across the app, particularly for
/// ISO8601 formatted dates from the backend API.
enum DateHelpers {
    /// Shared ISO8601 formatter
    /// - Note: ISO8601DateFormatter is thread-safe according to Apple documentation
    nonisolated(unsafe) private static let iso8601Formatter = ISO8601DateFormatter()

    /// Parse ISO8601 date string to Date
    ///
    /// Converts backend date strings (e.g., "2025-01-05T10:00:00Z") to Swift Date objects.
    ///
    /// - Parameter dateString: ISO8601 formatted string from API
    /// - Returns: Parsed Date or nil if string is nil or invalid
    ///
    /// **Usage:**
    /// ```swift
    /// let date = DateHelpers.parseISO8601("2025-01-05T10:00:00Z")
    /// let created = DateHelpers.parseISO8601(resource.attributes.created_at)
    /// ```
    static func parseISO8601(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        return iso8601Formatter.date(from: dateString)
    }

    /// Format Date to ISO8601 string
    ///
    /// Converts Swift Date objects to backend-compatible ISO8601 strings.
    ///
    /// - Parameter date: Date to format
    /// - Returns: ISO8601 formatted string (e.g., "2025-01-05T10:00:00Z")
    ///
    /// **Usage:**
    /// ```swift
    /// let dateString = DateHelpers.formatISO8601(Date())
    /// ```
    static func formatISO8601(_ date: Date) -> String {
        return iso8601Formatter.string(from: date)
    }
}
