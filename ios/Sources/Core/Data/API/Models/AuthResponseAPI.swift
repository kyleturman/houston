import Foundation

// MARK: - Auth Response API Models
//
// Response models for authentication endpoints.
// Magic links, invites, tokens, and user profile.

/// Response from claiming a magic link or invite token
struct MagicClaimResponse: Decodable {
    let device_token: String
    let user_token: String
    let server_name: String?
    let onboarding_completed: Bool
    let email_enabled: Bool?
}

/// Response from requesting a sign-in link
struct RequestSigninResponse: Decodable {
    let success: Bool
    let message: String
}

/// Response from refreshing a user token
struct TokenRefreshResponse: Decodable {
    let user_token: String
    let email: String
    let onboarding_completed: Bool
    let email_enabled: Bool?
}

/// Response for user profile operations
struct UserProfileResponse: Decodable {
    let email: String
    let name: String?
    let onboarding_completed: Bool
}

/// Response from ping endpoint
struct PingResponse: Decodable {
    let ok: Bool
}
