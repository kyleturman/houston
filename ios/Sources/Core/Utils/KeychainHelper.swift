import Foundation
import Security

/// Keychain operations wrapper for iOS Keychain
/// Used for storing sensitive data like encryption keys, tokens, etc.
///
/// **Security Properties:**
/// - Data encrypted by iOS Secure Enclave
/// - Survives app reinstalls
/// - Isolated per-app (sandboxed)
/// - Protected by device passcode/biometrics
///
/// **Thread-Safety:**
/// Individual Keychain operations are atomic at the system level, but compound
/// operations (check-then-act) may have race conditions. Callers should use
/// external locking for complex operations (e.g., get-or-create patterns).
///
/// Usage:
/// ```swift
/// // Save (creates or updates)
/// try KeychainHelper.save(key: "encryption_key", data: keyData)
///
/// // Load
/// if let data = KeychainHelper.load(key: "encryption_key") {
///     // Use data
/// }
///
/// // Delete
/// KeychainHelper.delete(key: "encryption_key")
/// ```
enum KeychainHelper {
    enum KeychainError: Error {
        case duplicateItem
        case unknown(OSStatus)
        case dataConversionError
    }

    // MARK: - Save

    /// Save data to Keychain (creates new item or updates existing)
    /// - Parameters:
    ///   - key: Unique identifier for this item
    ///   - data: Data to store (will be encrypted by iOS)
    ///   - accessibility: When this item should be accessible (default: afterFirstUnlock)
    /// - Throws: KeychainError if save fails
    static func save(
        key: String,
        data: Data,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock
    ) throws {
        // Try to create new item first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            // Successfully created new item
            return
        }

        if status == errSecDuplicateItem {
            // Item already exists, update it instead
            try update(key: key, data: data)
            return
        }

        // Other error
        throw KeychainError.unknown(status)
    }

    // MARK: - Load

    /// Load data from Keychain
    /// - Parameter key: Unique identifier for this item
    /// - Returns: Data if found, nil otherwise
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                // Log unexpected Keychain errors (but not "not found" which is normal)
                print("[KeychainHelper] ⚠️ Keychain load failed for key '\(key)': status \(status)")
            }
            return nil
        }

        return result as? Data
    }

    // MARK: - Update

    /// Update existing Keychain item
    /// - Parameters:
    ///   - key: Unique identifier for this item
    ///   - data: New data to store
    /// - Throws: KeychainError if update fails
    private static func update(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Delete

    /// Delete item from Keychain
    /// - Parameter key: Unique identifier for this item
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Clear All

    /// Delete all items stored by this app (use with caution!)
    /// Useful for logout or testing
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]

        SecItemDelete(query as CFDictionary)
    }
}
