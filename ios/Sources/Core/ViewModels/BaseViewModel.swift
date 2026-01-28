import Foundation
import SwiftUI

/// Base protocol for all ViewModels
/// Provides common functionality: loading state, error handling, API client creation
///
/// This is the foundation for all ViewModels in the app. It eliminates duplication
/// by providing default implementations for common ViewModel functionality.
///
/// **Modern iOS 17+ Pattern:**
/// Use the `@Observable` macro instead of `ObservableObject` for automatic observation.
/// No `@Published` annotations needed - all properties are automatically observable.
///
/// Usage:
/// ```swift
/// @MainActor
/// @Observable
/// class MyViewModel: BaseViewModel {
///     var loading: Bool = false  // No @Published needed!
///     var errorMessage: String?
///     var session: SessionManager
///
///     init(session: SessionManager) {
///         self.session = session
///     }
///
///     func loadData() async {
///         guard let client = makeClient() else { return }
///         // Use client to fetch data
///     }
/// }
/// ```
///
/// See also:
/// - `ResourceViewModel`: Extends BaseViewModel for list-based ViewModels
@MainActor
protocol BaseViewModel: AnyObject {
    /// Loading state - true when async operations are in progress
    var loading: Bool { get set }

    /// Error message to display to user
    var errorMessage: String? { get set }

    /// Session manager for authentication and server configuration
    var session: SessionManager { get set }
}

// Default implementations
extension BaseViewModel {
    /// Create an API client from the session
    /// Returns nil if server URL is not configured
    func makeClient() -> APIClient? {
        return session.makeClient()
    }

    /// Update the session reference (called when session changes)
    func setSession(_ session: SessionManager) {
        self.session = session
    }
}
