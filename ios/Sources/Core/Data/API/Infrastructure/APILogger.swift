import Foundation

// MARK: - API Logger
//
// Centralized logging for APIClient operations.
// Toggle `isEnabled` to control debug output.

enum APILogger {
    /// Enable/disable debug logging (set to false for production)
    /// Thread-safety: This is intentionally mutable for runtime toggling.
    /// Reads/writes are atomic for Bool on modern platforms.
    nonisolated(unsafe) static var isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Log debug messages (only when enabled)
    static func debug(_ message: String, path: String? = nil) {
        guard isEnabled else { return }
        if let path = path {
            print("[APIClient] \(message) - \(path)")
        } else {
            print("[APIClient] \(message)")
        }
    }

    /// Log error messages (always logged)
    static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            print("[APIClient] \(message): \(error)")
        } else {
            print("[APIClient] \(message)")
        }
    }

    /// Log cache hits (only when enabled)
    static func cacheHit(_ key: String, age: TimeInterval) {
        guard isEnabled else { return }
        let keyPreview = String(key.prefix(50))
        print("[APIClient] Cache hit for key: \(keyPreview) (age: \(Int(age))s)")
    }

    /// Log cache misses (only when enabled)
    static func cacheMiss(_ key: String, reason: String) {
        guard isEnabled else { return }
        let keyPreview = String(key.prefix(50))
        print("[APIClient] Cache \(reason) for key: \(keyPreview)")
    }

    /// Log cache operations (only when enabled)
    static func cacheOperation(_ operation: String, key: String, details: String? = nil) {
        guard isEnabled else { return }
        let keyPreview = String(key.prefix(50))
        if let details = details {
            print("[APIClient] \(operation) for key: \(keyPreview) (\(details))")
        } else {
            print("[APIClient] \(operation) for key: \(keyPreview)")
        }
    }

    /// Log decoding errors with context
    static func decodingError(_ error: Error, context: String, rawResponse: Data?) {
        print("[APIClient] Failed to decode \(context): \(error)")

        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let ctx):
                print("  Key '\(key.stringValue)' not found at path: \(ctx.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            case .typeMismatch(let type, let ctx):
                print("  Type mismatch for type \(type) at path: \(ctx.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            case .valueNotFound(let type, let ctx):
                print("  Value not found for type \(type) at path: \(ctx.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
            case .dataCorrupted(let ctx):
                print("  Data corrupted at path: \(ctx.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                print("  Debug description: \(ctx.debugDescription)")
            @unknown default:
                print("  Unknown decoding error")
            }
        }

        // Optionally log raw response preview for debugging
        if isEnabled, let rawResponse = rawResponse, let jsonString = String(data: rawResponse, encoding: .utf8) {
            print("  Raw response preview: \(jsonString.prefix(300))")
        }
    }
}
