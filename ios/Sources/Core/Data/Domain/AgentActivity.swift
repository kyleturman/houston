import Foundation

// MARK: - Agent Activity Domain Model
//
// Purpose:
//   Represents a complete agent execution loop with token usage, cost tracking,
//   tool usage, and performance metrics. Used for displaying activity history
//   and usage analytics.
//
// API Mapping:
//   Source: AgentActivityResource (Core/Data/API/AgentActivityAPI.swift)
//   Conversion: AgentActivityItem.from(resource:)
//   Key transforms:
//     - started_at/completed_at (String) → startedAt/completedAt (Date)
//     - cost_dollars (Double) → costDollars (Double)
//     - tools_called (Array) → toolsCalled (Array)
//
// Usage:
//   - Activity view (main activity list)
//   - Usage analytics
//   - Cost tracking displays
//
// Thread Safety:
//   - Struct (value type) safe for concurrent access
//   - Immutable properties (let) enforce read-only semantics

/// Single agent execution activity with usage metrics
///
/// Represents one complete agent loop execution, tracking tokens consumed,
/// cost, tools used, and execution time.
///
/// **Lifecycle:**
/// 1. Backend returns AgentActivityResource via JSON:API
/// 2. Decoded to AgentActivityResource in API layer
/// 3. Converted to AgentActivityItem via AgentActivityItem.from()
/// 4. Used in activity views for display
///
/// **Example:**
/// ```swift
/// let resource: AgentActivityResource = /* from API */
/// let activity = AgentActivityItem.from(resource: resource)
///
/// print("\(activity.agentTypeLabel): \(activity.formattedCost)")
/// print("Tools: \(activity.toolsSummary)")
/// print("Duration: \(activity.durationSeconds)s")
/// ```
struct AgentActivityItem: Identifiable, Equatable, @unchecked Sendable {
    // MARK: - Properties

    /// Unique identifier from backend
    let id: String

    /// Type of agent (goal, task, user_agent)
    let agentType: String

    /// Type of agentable entity (Goal, AgentTask, UserAgent)
    let agentableType: String

    /// ID of agentable entity
    let agentableId: String

    /// Associated goal ID (if any)
    let goalId: String?

    /// Input tokens consumed
    let inputTokens: Int

    /// Output tokens generated
    let outputTokens: Int

    /// Cost in cents
    let costCents: Int

    /// Cost in dollars
    let costDollars: Double

    /// Formatted cost string (e.g. "$0.15")
    let formattedCost: String

    /// Total tokens (input + output)
    let totalTokens: Int

    /// Number of tools called
    let toolCount: Int

    /// Array of tool names called
    let toolsCalled: [String]

    /// Human-readable tools summary
    let toolsSummary: String

    /// Number of iterations in loop
    let iterations: Int

    /// Execution duration in seconds
    let durationSeconds: Int

    /// Whether agent completed naturally (not hit max iterations)
    let naturalCompletion: Bool

    /// Human-readable agent type label
    let agentTypeLabel: String

    /// When execution started
    let startedAt: Date

    /// When execution completed
    let completedAt: Date

    /// Record creation timestamp
    let createdAt: Date

    /// Record update timestamp
    let updatedAt: Date

    // MARK: - Computed Properties

    /// Icon name for agent type
    var icon: String {
        switch agentType {
        case "goal":
            return "target"
        case "task":
            return "checkmark.circle"
        case "user_agent":
            return "sparkles"
        default:
            return "circle"
        }
    }

    /// Relative time ago string
    var relativeTimeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: completedAt, relativeTo: Date())
    }

    /// Formatted duration string
    var formattedDuration: String {
        if durationSeconds < 60 {
            return "\(durationSeconds)s"
        } else {
            let minutes = durationSeconds / 60
            let seconds = durationSeconds % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - API Conversion

extension AgentActivityItem {
    /// Converts API response model to domain model
    ///
    /// Transforms backend representation into Swift-idiomatic domain model.
    /// Parses ISO8601 dates and normalizes property names.
    ///
    /// - Parameter resource: AgentActivityResource from backend API
    /// - Returns: Domain model ready for app use
    ///
    /// **Example:**
    /// ```swift
    /// let resource = try decoder.decode(AgentActivityResource.self, from: data)
    /// let activity = AgentActivityItem.from(resource: resource)
    /// ```
    static func from(resource: AgentActivityResource) -> AgentActivityItem {
        let attrs = resource.attributes

        return AgentActivityItem(
            id: resource.id,
            agentType: attrs.agent_type,
            agentableType: attrs.agentable_type,
            agentableId: attrs.agentable_id,
            goalId: attrs.goal_id,
            inputTokens: attrs.input_tokens,
            outputTokens: attrs.output_tokens,
            costCents: attrs.cost_cents,
            costDollars: attrs.cost_dollars,
            formattedCost: attrs.formatted_cost,
            totalTokens: attrs.total_tokens,
            toolCount: attrs.tool_count,
            toolsCalled: attrs.tools_called,
            toolsSummary: attrs.tools_summary,
            iterations: attrs.iterations,
            durationSeconds: attrs.duration_seconds,
            naturalCompletion: attrs.natural_completion,
            agentTypeLabel: attrs.agent_type_label,
            startedAt: DateHelpers.parseISO8601(attrs.started_at) ?? Date(),
            completedAt: DateHelpers.parseISO8601(attrs.completed_at) ?? Date(),
            createdAt: DateHelpers.parseISO8601(attrs.created_at) ?? Date(),
            updatedAt: DateHelpers.parseISO8601(attrs.updated_at) ?? Date()
        )
    }
}
