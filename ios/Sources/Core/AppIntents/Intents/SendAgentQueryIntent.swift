import AppIntents
import SwiftUI

@available(iOS 16.0, *)
struct SendAgentQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Agent"
    static let description = IntentDescription("Send a query to your Houston agent")
    static let openAppWhenRun: Bool = false // Fire-and-forget, notification when complete

    @Parameter(title: "Query", description: "What would you like your agent to do?")
    var query: String

    @Parameter(title: "Goal", description: "Optional goal context for the query")
    var goal: GoalEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Create API client from shared credentials
        let client: IntentAPIClient
        do {
            client = try IntentAPIClient.create()
        } catch {
            throw IntentError.notAuthenticated
        }

        // Send query to backend (fire-and-forget)
        do {
            _ = try await client.sendAgentQuery(
                query: query,
                goalId: goal?.id
            )

            let message = "I'm working on it! You'll get a notification when I'm done."

            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            let errorMsg: String
            if let apiError = error as? ExtensionAPIClient.APIError {
                switch apiError {
                case .requestFailed(let statusCode, let message):
                    if statusCode == 401 {
                        errorMsg = "Session expired. Please open the app and sign in again."
                    } else {
                        errorMsg = message ?? "Failed to send query"
                    }
                default:
                    errorMsg = "Failed to send query: \(error.localizedDescription)"
                }
            } else {
                errorMsg = "Failed to send query: \(error.localizedDescription)"
            }

            throw IntentError.networkError(errorMsg)
        }
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Ask agent: \(\.$query)") {
            \.$goal
        }
    }
}
