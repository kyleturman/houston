import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Note"
    static let description = IntentDescription("Quickly add a note to Houston")
    static let openAppWhenRun: Bool = false // Run in background

    @Parameter(title: "Note Content", description: "The content of the note")
    var content: String

    @Parameter(title: "Note Title", description: "Optional title for the note")
    var title: String?

    @Parameter(title: "Goal", description: "Optional goal to associate the note with")
    var goal: GoalEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Create API client from shared credentials
        let client: IntentAPIClient
        do {
            client = try IntentAPIClient.create()
        } catch {
            _ = (error as? IntentError)?.errorDescription ?? "Not signed in"
            throw IntentError.notAuthenticated
        }

        // Save note via API
        do {
            let goalId = goal?.id
            _ = try await client.createNote(
                title: title,
                content: content,
                goalId: goalId
            )

            let goalName = goal?.title ?? "your notes"
            let message = "Note saved to \(goalName)"

            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            let errorMsg: String
            if let apiError = error as? ExtensionAPIClient.APIError {
                switch apiError {
                case .requestFailed(let statusCode, let message):
                    if statusCode == 401 {
                        errorMsg = "Session expired. Please open the app and sign in again."
                    } else {
                        errorMsg = message ?? "Failed to save note"
                    }
                default:
                    errorMsg = "Failed to save note: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "Failed to save note: \(error.localizedDescription)"
            }

            throw IntentError.networkError(errorMsg)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Add note: \(\.$content)") {
            \.$title
            \.$goal
        }
    }
}

// Note: AppShortcuts are now registered in AppShortcuts.swift
// Only one AppShortcutsProvider is allowed per app
