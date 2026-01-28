import Foundation
import SwiftUI

// MARK: - Task Domain Model
//
// Purpose:
//   Represents an agent task with status tracking, priority, retry logic,
//   and error handling. Tasks are autonomous operations performed by the agent
//   on behalf of the user.
//
// API Mapping:
//   Source: AgentTaskResource (Core/Models/API/TaskAPI.swift)
//   Conversion: AgentTaskModel.from(resource:)
//   Key transforms:
//     - created_at (String?) → createdAt (Date?)
//     - updated_at (String?) → updatedAt (Date?)
//     - next_retry_at (String?) → nextRetryAt (Date?)
//     - status (String) → status (Status enum)
//     - priority (String) → priority (Priority enum)
//     - goal_id (String?) → goalId (String?)
//
// Usage:
//   - Task list/detail views (TasksView, AgentTaskDetailView)
//   - Agent task execution and monitoring
//   - Retry management for failed tasks
//
// UI Coupling:
//   - Contains SwiftUI Color for statusColor (accepted design decision)
//   - @MainActor requirement for color access
//   - Provides display helpers for UI consistency
//
// Persistence:
//   - Not Codable (no App Group sync needed)
//   - Standard Equatable implementation
//
// Thread Safety:
//   - Struct (value type) safe for concurrent access
//   - Mutable properties for status updates
//   - @MainActor required for statusColor access

/// Agent task with execution tracking and retry logic
///
/// Tasks represent autonomous operations the agent performs. Each task
/// has status tracking, priority, error handling, and automatic retry logic.
///
/// **Lifecycle:**
/// 1. Backend returns AgentTaskResource via JSON:API
/// 2. Decoded to AgentTaskResource in API layer
/// 3. Converted to AgentTaskModel via AgentTaskModel.from(resource:)
/// 4. Used in views and monitoring systems
///
/// **Concurrency:**
/// - Swift 6: Conforms to Sendable for safe concurrent access
///
/// **Example:**
/// ```swift
/// let resource: AgentTaskResource = /* from API */
/// let task = AgentTaskModel.from(resource: resource)
///
/// // Check status and retry
/// if task.status == .paused && task.isRetryable {
///     print(task.retryStatusText)
/// }
/// ```
struct AgentTaskModel: Identifiable, Equatable, Sendable {
    // MARK: - Properties

    /// Unique identifier from backend
    let id: String

    /// Task title/description
    var title: String

    /// Detailed instructions for the agent
    /// - Note: Guides agent behavior when executing task
    var instructions: String?

    /// Current execution status
    var status: Status

    /// Task priority level
    var priority: Priority

    /// Associated goal ID if task belongs to a goal
    /// - Note: String ID per JSON:API best practice
    var goalId: String?

    /// When the task was created
    var createdAt: Date?

    /// When the task was last updated
    var updatedAt: Date?

    /// Error type for failed/paused tasks
    /// - Note: Used for retry logic and user messages
    /// - Examples: "rate_limit", "network", "timeout", "mcp_error"
    var errorType: String?

    /// Detailed error message from failure
    /// - Note: May contain technical details
    var errorMessage: String?

    /// Number of retry attempts made
    /// - Note: Used with maxRetries to determine if task can retry
    var retryCount: Int?

    /// When the next automatic retry will occur
    /// - Note: Set by backend retry scheduler
    var nextRetryAt: Date?

    /// Reason for manual cancellation
    /// - Note: Only set when status is .cancelled
    var cancelledReason: String?

    // MARK: - Nested Types

    /// Task execution status
    ///
    /// Represents the current state of task execution and determines
    /// what actions are available (retry, cancel, etc.).
    enum Status: String, Codable {
        /// Task is currently running or queued
        case active

        /// Task finished successfully
        case completed

        /// Task failed and is awaiting retry
        case paused

        /// Task was manually cancelled
        case cancelled
    }

    /// Task priority level
    ///
    /// Determines execution order when multiple tasks are queued.
    /// Higher priority tasks are executed first.
    enum Priority: String, Codable {
        /// Low priority - background task
        case low

        /// Normal priority - standard task (default)
        case normal

        /// High priority - important task
        case high

        /// Critical priority - urgent task
        case critical
    }

    // MARK: - Computed Properties - Display

    /// Color for status display in UI
    ///
    /// Maps task status to semantic color scheme.
    /// Must be accessed from main actor due to Color requirement.
    ///
    /// **Colors:**
    /// - active: info (blue)
    /// - completed: success (green)
    /// - paused: warning (yellow)
    /// - cancelled: error (red)
    ///
    /// - Note: Requires @MainActor context
    /// - Returns: Semantic color for current status
    @MainActor
    var statusColor: Color {
        switch status {
        case .active: return Color.semantic["info"]
        case .completed: return Color.semantic["success"]
        case .paused: return Color.semantic["warning"]
        case .cancelled: return Color.semantic["error"]
        }
    }

    /// User-facing status name
    ///
    /// Provides capitalized display name for status enum.
    ///
    /// - Returns: Display name (e.g., "Active", "Completed")
    var statusDisplayName: String {
        switch status {
        case .active: return "Active"
        case .completed: return "Completed"
        case .paused: return "Paused"
        case .cancelled: return "Cancelled"
        }
    }

    /// User-friendly error message
    ///
    /// Converts technical error types into readable messages.
    /// Falls back to raw error message if type is unknown.
    ///
    /// **Error Types:**
    /// - "rate_limit": API rate limiting
    /// - "network"/"timeout": Connection issues
    /// - "mcp_error": External tool errors
    ///
    /// - Returns: Human-readable error message (truncated to 100 chars)
    var userFriendlyErrorMessage: String {
        guard let errorType = errorType else { return "Unknown error" }

        switch errorType {
        case "rate_limit":
            return "API was rate limited"
        case "network", "timeout":
            return "Network connection issue"
        case "mcp_error":
            return "External tool error"
        default:
            return errorMessage?.prefix(100).description ?? "Unknown error occurred"
        }
    }

    // MARK: - Computed Properties - Retry Logic

    /// Whether the task can be retried
    ///
    /// Determines if task has remaining retry attempts based on:
    /// - Current status (must be paused)
    /// - Retry count vs max retries for error type
    ///
    /// **Max Retries by Error Type:**
    /// - rate_limit: 5 retries (backoff for rate limits)
    /// - network/timeout: 3 retries (transient issues)
    /// - other: 2 retries (likely persistent problems)
    ///
    /// - Returns: True if task can retry, false otherwise
    var isRetryable: Bool {
        guard status == .paused, let retryCount = retryCount else { return false }

        let maxRetries: Int
        switch errorType {
        case "rate_limit":
            maxRetries = 5
        case "network", "timeout":
            maxRetries = 3
        default:
            maxRetries = 2
        }

        return retryCount < maxRetries
    }

    /// Time remaining until next automatic retry
    ///
    /// Calculates seconds until nextRetryAt, clamped to 0 if in the past.
    ///
    /// - Returns: Seconds until retry, nil if no retry scheduled
    var timeUntilRetry: TimeInterval? {
        guard let nextRetryAt = nextRetryAt else { return nil }
        let timeInterval = nextRetryAt.timeIntervalSinceNow
        return timeInterval > 0 ? timeInterval : 0
    }

    /// Human-readable retry countdown text
    ///
    /// Formats time until retry as "Xm Ys" or "Xs" for display.
    /// Shows "Ready to retry" if time has elapsed.
    ///
    /// **Examples:**
    /// - "Retrying in 2m 30s"
    /// - "Retrying in 45s"
    /// - "Ready to retry"
    ///
    /// - Returns: Formatted retry status text, empty if not paused
    var retryStatusText: String {
        guard status == .paused else { return "" }

        if let timeUntilRetry = timeUntilRetry, timeUntilRetry > 0 {
            let minutes = Int(timeUntilRetry / 60)
            let seconds = Int(timeUntilRetry.truncatingRemainder(dividingBy: 60))

            if minutes > 0 {
                return "Retrying in \(minutes)m \(seconds)s"
            } else {
                return "Retrying in \(seconds)s"
            }
        } else {
            return "Ready to retry"
        }
    }
}

// MARK: - API Conversion

extension AgentTaskModel {
    /// Converts API response model to domain model
    ///
    /// Transforms backend representation into Swift-idiomatic domain model.
    /// Parses ISO8601 dates and maps string enums.
    ///
    /// - Parameter resource: AgentTaskResource from backend API
    /// - Returns: Domain model ready for app use
    ///
    /// **Transformations:**
    /// - ISO8601 strings → Date objects (created_at, updated_at, next_retry_at)
    /// - status string → Status enum (defaults to .active if unknown)
    /// - priority string → Priority enum (defaults to .normal if unknown)
    /// - snake_case → camelCase property names
    ///
    /// **Example:**
    /// ```swift
    /// let resource = try decoder.decode(AgentTaskResource.self, from: data)
    /// let task = AgentTaskModel.from(resource: resource)
    /// print(task.statusDisplayName)
    /// ```
    static func from(resource: AgentTaskResource) -> AgentTaskModel {
        let a = resource.attributes

        // Parse ISO8601 date strings to Date objects
        let created = DateHelpers.parseISO8601(a.created_at)
        let updated = DateHelpers.parseISO8601(a.updated_at)
        let nextRetry = DateHelpers.parseISO8601(a.next_retry_at)

        return AgentTaskModel(
            id: resource.id,
            title: a.title,
            instructions: a.instructions,
            status: Status(rawValue: a.status) ?? .active,
            priority: Priority(rawValue: a.priority) ?? .normal,
            goalId: a.goal_id,
            createdAt: created,
            updatedAt: updated,
            errorType: a.error_type,
            errorMessage: a.error_message,
            retryCount: a.retry_count,
            nextRetryAt: nextRetry,
            cancelledReason: a.cancelled_reason
        )
    }
}
