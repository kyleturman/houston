import Foundation

enum AppConfig {
    // Reads the app URL scheme from Info.plist (CFBundleURLTypes -> CFBundleURLSchemes[0]).
    // Keep this in sync with the backend .env APP_URL_SCHEME used in emails.
    static var appURLScheme: String? {
        if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
           let first = urlTypes.first,
           let schemes = first["CFBundleURLSchemes"] as? [String],
           let scheme = schemes.first {
            return scheme
        }
        return nil
    }
}
