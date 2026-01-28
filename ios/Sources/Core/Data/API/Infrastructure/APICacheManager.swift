import Foundation
import CryptoKit

// MARK: - API Cache Manager
//
// Handles encrypted caching of API responses.
// Features:
// - AES-256-GCM encryption at rest
// - Version-based cache invalidation
// - Automatic expiry
// - Resource-based cache invalidation

final class APICacheManager: @unchecked Sendable {

    // MARK: - Configuration

    /// Cache version - use date when API response schemas change (YYYY-MM-DD format)
    /// This ensures old cached data with incompatible schemas is automatically invalidated
    /// Add suffix (-a, -b) if multiple changes occur on same day
    ///
    /// History:
    /// - 2025-09-18: Initial version
    /// - 2025-11-05: Changed goal_id from Int to String (JSON:API best practice)
    /// - 2025-11-06: Fixed tool_activity metadata structure (must be object, not string)
    /// - 2025-11-20: Fixed feed timezone bug + made DiscoveryData.source optional
    /// - 2025-11-21: Added AgentActivity API models for activity tracking
    /// - 2025-11-25: Added agent_history_id to ThreadMessage, session pagination
    let cacheVersion = "2025-11-25"

    /// Cache expiry duration (24 hours)
    let cacheExpiry: TimeInterval = 86400

    /// Maximum cache size (10 MB)
    let maxCacheSize = 10 * 1024 * 1024

    /// User token provider for cache key generation
    private let userTokenProvider: () -> String?

    // MARK: - Encryption

    /// Keychain key for cache encryption
    private static let cacheEncryptionKeyName = "houston_cache_encryption_key"

    /// Lock for thread-safe key generation
    private static let keyGenerationLock = NSLock()

    /// Cached encryption key (avoids repeated Keychain access)
    nonisolated(unsafe) private static var cachedEncryptionKey: SymmetricKey?

    // MARK: - Initialization

    init(userTokenProvider: @escaping () -> String?) {
        self.userTokenProvider = userTokenProvider
        clearOldCacheVersions()
    }

    // MARK: - Cache Key Generation

    /// Generate cache key from request path and auth
    /// Uses stable hash of user token (not hashValue which changes between launches)
    /// Includes cache version to automatically invalidate old cached data on schema changes
    func cacheKey(for path: String) -> String {
        let userIdentifier: String
        if let token = userTokenProvider(), !token.isEmpty {
            userIdentifier = String(token.prefix(16))
        } else {
            userIdentifier = "none"
        }
        return "cache:\(cacheVersion):\(path):\(userIdentifier)"
    }

    // MARK: - Cache Read/Write

    /// Load cached response data
    /// Data is encrypted at rest using AES-256-GCM
    /// IMPORTANT: Runs on background thread to avoid blocking main thread
    func loadCachedResponse(key: String) async -> Data? {
        return await Task.detached { [self] in
            guard let encryptedData = UserDefaults.standard.data(forKey: key),
                  let cacheInfo = UserDefaults.standard.dictionary(forKey: "\(key):meta"),
                  let timestamp = cacheInfo["timestamp"] as? TimeInterval else {
                return nil
            }

            // Check if cache is expired
            let age = Date().timeIntervalSince1970 - timestamp
            if age > self.cacheExpiry {
                APILogger.cacheMiss(key, reason: "expired")
                self.clearCache(key: key)
                return nil
            }

            // Decrypt cached data (CPU-intensive, runs on background thread)
            guard let decryptedData = self.decryptCacheData(encryptedData) else {
                APILogger.cacheMiss(key, reason: "decryption failed")
                self.clearCache(key: key)
                return nil
            }

            APILogger.cacheHit(key, age: age)
            return decryptedData
        }.value
    }

    /// Save response data to cache
    /// Data is encrypted using AES-256-GCM before storage
    func cacheResponse(_ data: Data, key: String) {
        // Don't cache if response is too large
        guard data.count < maxCacheSize else {
            APILogger.debug("Response too large to cache (\(data.count) bytes)")
            return
        }

        // Encrypt data before storing
        guard let encryptedData = encryptCacheData(data) else {
            APILogger.error("Failed to encrypt cache", error: nil)
            return
        }

        let meta: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "size": data.count,
            "encrypted": true
        ]

        UserDefaults.standard.set(encryptedData, forKey: key)
        UserDefaults.standard.set(meta, forKey: "\(key):meta")
        APILogger.cacheOperation("Cached encrypted response", key: key, details: "\(data.count) bytes")
    }

    // MARK: - Cache Clearing

    /// Clear specific cache entry
    func clearCache(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: "\(key):meta")
    }

    /// Clear all cache entries (call on logout)
    func clearAllCache() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("cache:") }
        keys.forEach { defaults.removeObject(forKey: $0) }
        APILogger.debug("Cleared all cache entries (\(keys.count) keys)")
    }

    /// Clear cache entries from old versions
    /// Called automatically on init to invalidate caches when schema changes
    private func clearOldCacheVersions() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        let currentVersionPrefix = "cache:\(cacheVersion):"

        let oldKeys = allKeys.filter { key in
            key.hasPrefix("cache:") && !key.hasPrefix(currentVersionPrefix)
        }

        if !oldKeys.isEmpty {
            oldKeys.forEach { defaults.removeObject(forKey: $0) }
            APILogger.debug("Cleared \(oldKeys.count) old cache entries from previous versions")
        }
    }

    /// Invalidate cache for a specific API path
    func clearCacheForPath(_ path: String) {
        let key = cacheKey(for: path)
        clearCache(key: key)
        APILogger.debug("Cleared cache for path: \(path)")
    }

    /// Invalidate multiple cache paths matching a pattern
    func clearCachesMatchingPattern(_ pattern: String) {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys

        let matchingKeys = allKeys.filter { key in
            key.hasPrefix("cache:") && key.contains(pattern)
        }

        matchingKeys.forEach {
            defaults.removeObject(forKey: $0)
            defaults.removeObject(forKey: "\($0):meta")
        }

        if !matchingKeys.isEmpty {
            APILogger.debug("Cleared \(matchingKeys.count) cache entries matching pattern: \(pattern)")
        }
    }

    /// Invalidate related caches when a resource is mutated
    /// Maps resource types to all affected cache paths
    func invalidateRelatedCaches(forResourceType resourceType: String, resourceId: String, action: String) {
        switch (resourceType, action) {
        case ("goal", "created"), ("goal", "updated"):
            clearCacheForPath("/api/goals")
            clearCacheForPath("/api/goals/\(resourceId)")

        case ("goal", "deleted"):
            clearCacheForPath("/api/goals")
            clearCacheForPath("/api/goals/\(resourceId)")
            clearCachesMatchingPattern("/api/goals/\(resourceId)/notes")
            clearCachesMatchingPattern("/api/goals/\(resourceId)/agent_tasks")
            clearCachesMatchingPattern("/api/goals/\(resourceId)/activity")
            clearCachesMatchingPattern("/api/goals/\(resourceId)/thread")

        case ("note", "created"), ("note", "updated"):
            clearCacheForPath("/api/notes")
            clearCachesMatchingPattern("/api/goals/")

        case ("note", "deleted"):
            clearCacheForPath("/api/notes")
            clearCachesMatchingPattern("/api/goals/")
            clearCacheForPath("/api/notes/\(resourceId)")

        case ("task", "created"), ("task", "updated"), ("task", "completed"):
            clearCachesMatchingPattern("/api/goals/")
            clearCacheForPath("/api/agent_tasks/\(resourceId)")

        case ("task", "deleted"):
            clearCachesMatchingPattern("/api/goals/")
            clearCacheForPath("/api/agent_tasks/\(resourceId)")

        case ("feed", "generated"):
            clearCacheForPath("/api/feed/current")
            clearCacheForPath("/api/feed/history")

        case ("thread_message", "created"):
            clearCachesMatchingPattern("/api/goals/")
            clearCachesMatchingPattern("/api/agent_tasks/")
            clearCachesMatchingPattern("/api/user_agent/thread")

        case ("agent_history", "deleted"):
            // Clear agent history list caches for both goals and user agent
            clearCachesMatchingPattern("/api/goals/")
            clearCachesMatchingPattern("/api/user_agent/agent_histories")

        case ("agent_history", "reset"):
            // Current session was reset - clear thread message and agent history caches
            clearCachesMatchingPattern("/api/goals/")
            clearCachesMatchingPattern("/api/user_agent/agent_histories")
            clearCachesMatchingPattern("/api/user_agent/thread")

        default:
            APILogger.debug("Cache invalidation: unknown resource type '\(resourceType)' with action '\(action)'")
        }
    }

    // MARK: - Cache-Then-Network Helper

    /// Load from cache only (no network request)
    /// Returns nil if no cache exists or cache is expired
    func loadFromCacheOnly(path: String) async -> Data? {
        let key = cacheKey(for: path)
        return await loadCachedResponse(key: key)
    }

    // MARK: - Encryption Helpers

    /// Get or create encryption key for cache
    /// Key is stored in iOS Keychain and survives app reinstalls
    private func getCacheEncryptionKey() throws -> SymmetricKey {
        Self.keyGenerationLock.lock()
        defer { Self.keyGenerationLock.unlock() }

        if let cached = Self.cachedEncryptionKey {
            return cached
        }

        if let keyData = KeychainHelper.load(key: Self.cacheEncryptionKeyName) {
            let key = SymmetricKey(data: keyData)
            Self.cachedEncryptionKey = key
            return key
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        try KeychainHelper.save(key: Self.cacheEncryptionKeyName, data: keyData)

        Self.cachedEncryptionKey = newKey
        APILogger.debug("Generated new cache encryption key")
        return newKey
    }

    /// Encrypt data using AES-GCM
    private func encryptCacheData(_ data: Data) -> Data? {
        do {
            let key = try getCacheEncryptionKey()
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            APILogger.error("Cache encryption failed", error: error)
            return nil
        }
    }

    /// Decrypt data using AES-GCM
    private func decryptCacheData(_ encryptedData: Data) -> Data? {
        do {
            let key = try getCacheEncryptionKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            APILogger.error("Cache decryption failed", error: error)
            return nil
        }
    }
}
