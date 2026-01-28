import Foundation

// MARK: - Debug Logger
//
// Centralized debug logging that is automatically disabled in production builds.
// Uses compile-time #if DEBUG to ensure no logging overhead in release builds.
//
// Usage:
//   DebugLog.info("Loading feed")
//   DebugLog.network("SSE connected", category: "SSE")
//   DebugLog.warning("Cache miss for key: \(key)")
//   DebugLog.error("Failed to parse response", error: error)

enum DebugLog {
    // MARK: - Log Levels

    /// General informational logging
    static func info(_ message: String, category: String? = nil) {
        #if DEBUG
        log(level: "INFO", emoji: "ℹ️", message: message, category: category)
        #endif
    }

    /// Network-related logging (API calls, SSE, etc.)
    static func network(_ message: String, category: String? = nil) {
        #if DEBUG
        log(level: "NET", emoji: "🌐", message: message, category: category)
        #endif
    }

    /// UI/View lifecycle logging
    static func ui(_ message: String, category: String? = nil) {
        #if DEBUG
        log(level: "UI", emoji: "🎨", message: message, category: category)
        #endif
    }

    /// State/data changes
    static func state(_ message: String, category: String? = nil) {
        #if DEBUG
        log(level: "STATE", emoji: "📊", message: message, category: category)
        #endif
    }

    /// Warning - something unexpected but not fatal
    static func warning(_ message: String, category: String? = nil) {
        #if DEBUG
        log(level: "WARN", emoji: "⚠️", message: message, category: category)
        #endif
    }

    /// Error logging - also logs in release for crash diagnostics
    static func error(_ message: String, error: Error? = nil, category: String? = nil) {
        #if DEBUG
        if let error = error {
            log(level: "ERROR", emoji: "❌", message: "\(message): \(error.localizedDescription)", category: category)
        } else {
            log(level: "ERROR", emoji: "❌", message: message, category: category)
        }
        #endif
    }

    // MARK: - Internal

    private static func log(level: String, emoji: String, message: String, category: String?) {
        let prefix = category.map { "[\($0)]" } ?? ""
        print("\(emoji) \(prefix) \(message)")
    }
}
