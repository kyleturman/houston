import Foundation
import Observation

/// Stores information about the most recently signed-out user for "Sign back in" functionality
struct RememberedUser: Codable, Equatable {
    let serverURL: String
    let serverName: String
    let email: String
    let savedAt: Date
    /// Whether the server has email configured (for magic link sign-in)
    /// Defaults to true for backwards compatibility with older stored data
    var emailEnabled: Bool = true
}

@MainActor
@Observable
final class RememberedUserStore {
    private static let key = "remembered_user"

    private(set) var rememberedUser: RememberedUser?

    var hasRememberedUser: Bool { rememberedUser != nil }

    init() {
        load()
    }

    /// Remember a user's server info for re-signing in
    /// - Parameters:
    ///   - serverURL: The server URL
    ///   - serverName: The display name of the server
    ///   - email: The user's email address
    ///   - emailEnabled: Whether the server has email configured (for magic link sign-in)
    func remember(serverURL: URL, serverName: String, email: String, emailEnabled: Bool = true) {
        let user = RememberedUser(
            serverURL: serverURL.absoluteString,
            serverName: serverName,
            email: email,
            savedAt: Date(),
            emailEnabled: emailEnabled
        )
        rememberedUser = user
        persist()
        print("[RememberedUserStore] Remembered user: \(email) at \(serverName), emailEnabled: \(emailEnabled)")
    }

    /// Forget the remembered user (complete sign out)
    func forget() {
        if let user = rememberedUser {
            print("[RememberedUserStore] Forgetting user: \(user.email)")
        }
        rememberedUser = nil
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(RememberedUser.self, from: data) else {
            return
        }
        rememberedUser = decoded
        print("[RememberedUserStore] Loaded remembered user: \(decoded.email)")
    }

    private func persist() {
        guard let user = rememberedUser,
              let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
