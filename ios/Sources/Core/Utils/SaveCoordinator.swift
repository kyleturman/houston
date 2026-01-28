import Foundation
import SwiftUI

/// Coordinates save operations with standardized toast feedback
/// Eliminates duplicated toast and error handling patterns
///
/// Usage:
/// ```swift
/// // Optimistic save (dismiss immediately, save in background)
/// await SaveCoordinator.optimisticSave(
///     loadingMessage: "Saving note...",
///     successMessage: "Note saved",
///     operation: {
///         try await client.createNote(title: title, content: content)
///     }
/// )
///
/// // Blocking save (wait for result, keep sheet open on error)
/// let result = await SaveCoordinator.blockingSave(
///     operation: {
///         try await client.updateProfile(name: name)
///     }
/// )
/// if case .success = result {
///     dismiss()
/// }
/// ```
@MainActor
struct SaveCoordinator {
    /// Result of a save operation
    enum SaveResult<T> {
        case success(T)
        case failure(String)
    }

    /// Extract user-friendly error message from an error
    static func extractErrorMessage(from error: Error) -> String {
        // Try to extract backend error message
        if let apiError = error as? APIClient.APIError,
           case .requestFailed(_, let message) = apiError,
           let message = message,
           let data = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let backendError = json["error"] as? String {
            return backendError
        }

        // Fallback to generic message
        return "Operation failed"
    }

    /// Perform an optimistic save operation
    /// - Shows loading toast immediately
    /// - Executes operation in background
    /// - Updates toast on success/failure
    /// - Returns immediately (non-blocking)
    ///
    /// Use for: Notes, Tasks, Goals - operations where UI updates optimistically
    static func optimisticSave<T>(
        loadingMessage: String,
        successMessage: String,
        failureMessage: String = "Operation failed",
        operation: @escaping () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        onFailure: ((String) -> Void)? = nil
    ) async {
        let toastId = ToastManager.shared.showLoading(loadingMessage)

        Task {
            do {
                let result = try await operation()

                await MainActor.run {
                    ToastManager.shared.updateToast(id: toastId, message: successMessage, type: .success)
                    onSuccess?(result)
                }
            } catch {
                let errorMessage = extractErrorMessage(from: error)

                await MainActor.run {
                    ToastManager.shared.updateToast(id: toastId, message: errorMessage, type: .error)
                    onFailure?(errorMessage)
                }
            }
        }
    }

    /// Perform a blocking save operation
    /// - Executes operation and waits for result
    /// - Shows toast feedback
    /// - Returns success/failure result
    ///
    /// Use for: Settings, Forms - operations where sheet stays open on error
    static func blockingSave<T>(
        loadingMessage: String? = nil,
        successMessage: String? = nil,
        failureMessage: String = "Operation failed",
        operation: @escaping () async throws -> T
    ) async -> SaveResult<T> {
        // Show loading toast if message provided
        let toastId = loadingMessage.map { ToastManager.shared.showLoading($0) }

        do {
            let result = try await operation()

            // Show success toast if message provided
            if let toastId = toastId, let successMessage = successMessage {
                ToastManager.shared.updateToast(id: toastId, message: successMessage, type: .success)
            } else if let successMessage = successMessage {
                ToastManager.shared.show(successMessage, type: .success)
            }

            return .success(result)
        } catch {
            let errorMessage = extractErrorMessage(from: error)

            // Show error toast
            if let toastId = toastId {
                ToastManager.shared.updateToast(id: toastId, message: errorMessage, type: .error)
            } else {
                ToastManager.shared.show(errorMessage, type: .error)
            }

            return .failure(errorMessage)
        }
    }

    /// Perform a save operation without toast feedback
    /// - Useful when you want to handle UI feedback manually
    /// - Returns success/failure result
    static func silentSave<T>(
        operation: @escaping () async throws -> T
    ) async -> SaveResult<T> {
        do {
            let result = try await operation()
            return .success(result)
        } catch {
            let errorMessage = extractErrorMessage(from: error)
            return .failure(errorMessage)
        }
    }

    /// Update an existing toast from loading to success/error
    /// - Useful when you manage the loading toast yourself
    static func updateToast(
        id: UUID,
        success: Bool,
        successMessage: String,
        failureMessage: String = "Operation failed",
        error: Error? = nil
    ) {
        if success {
            ToastManager.shared.updateToast(id: id, message: successMessage, type: .success)
        } else {
            let errorMessage = error.map { extractErrorMessage(from: $0) } ?? failureMessage
            ToastManager.shared.updateToast(id: id, message: errorMessage, type: .error)
        }
    }
}
