import Foundation

// MARK: - Goal Domain Model
//
// Purpose:
//   Represents a user goal with status tracking, learnings, agent instructions,
//   and runtime state for check-ins and ideas. Goals are the primary organizational
//   unit in the app, containing notes, tasks, and activity history.
//
// API Mapping:
//   Source: GoalResource (Core/Models/API/GoalAPI.swift)
//   Conversion: Goal.from(resource:)
//   Key transforms:
//     - created_at (String?) → createdAt (Date?)
//     - updated_at (String?) → updatedAt (Date?)
//     - status (String) → status (Status enum)
//     - accent_color (String?) → accentColor (String?)
//     - enabled_mcp_servers ([String]?) → enabledMcpServers ([String]?)
//     - runtime_state (AnyDecodable?) → runtimeState ([String: Any]?)
//
// Usage:
//   - Goal list/detail views (GoalView, HomeView)
//   - Goal creation/editing (GoalFormView, GoalCreationSheet)
//   - App Group sync (Share Extension needs Codable)
//   - Navigation (GoalEntity for App Intents)
//
// Persistence:
//   - Codable for App Group UserDefaults sync
//   - runtimeState excluded from encoding (non-Codable dictionary)
//   - isSyncing excluded from API (UI-only state)
//
// Thread Safety:
//   - Struct (value type) safe for concurrent access
//   - Mutable properties for local updates

/// User goal with status, progress, and agent configuration
///
/// Goals represent user objectives that the AI agent helps achieve.
/// Each goal can have agent instructions, learnings, enabled MCP servers,
/// and runtime state for check-ins and ideas.
///
/// **Lifecycle:**
/// 1. Backend returns GoalResource via JSON:API
/// 2. Decoded to GoalResource in API layer
/// 3. Converted to Goal via Goal.from(resource:)
/// 4. Used in views and synced to App Group for Share Extension
///
/// **Concurrency:**
/// - Swift 6: Conforms to @unchecked Sendable for safe concurrent access
/// - runtimeState contains non-Sendable [String: Any] but is immutable after creation
/// - @unchecked is safe because: structs are value types, dictionary is never mutated after init
///
/// **Example:**
/// ```swift
/// let resource: GoalResource = /* from API */
/// let goal = Goal.from(resource: resource)
///
/// // Access properties
/// print(goal.title)
/// if let nextCheckIn = goal.nextCheckIn {
///     print("Next check-in: \(nextCheckIn.scheduledFor)")
/// }
/// ```
struct Goal: Identifiable, Codable, @unchecked Sendable {
    // MARK: - Constants

    /// Default MCP servers enabled for new goals
    /// - Note: Brave Search provides web search capability by default
    static let defaultEnabledMcpServers: [String] = ["brave-search"]

    // MARK: - Properties

    /// Unique identifier from backend
    let id: String

    /// Goal title (user-facing name)
    var title: String

    /// Optional detailed description
    var description: String?

    /// Current status of the goal
    var status: Status

    /// Hex color code for UI accent (e.g., "#FF5733")
    var accentColor: String?

    /// Instructions for the AI agent
    /// - Note: Guides agent behavior when working on this goal
    var agentInstructions: String?

    /// Enabled MCP server identifiers
    /// - Note: MCP servers provide tools/resources for the agent
    var enabledMcpServers: [String]?

    /// Count of enabled MCP servers that are actually available/connected
    /// - Note: From backend - filters out disconnected/disabled servers
    var activeMcpServersCount: Int?

    /// Agent learnings about the goal
    /// - Format: Array of dictionaries with "content" and "created_at" keys
    /// - Note: Accumulated knowledge from agent interactions
    var learnings: [[String: String]]?

    /// Runtime state from agent (check-ins, ideas, etc.)
    /// - Note: Not Codable - excluded from persistence
    /// - Format: Flexible dictionary structure from backend
    var runtimeState: [String: Any]?

    /// When the goal was created
    var createdAt: Date?

    /// When the goal was last updated
    var updatedAt: Date?

    /// Display order for goal list
    /// - Note: Lower numbers appear first in lists
    var displayOrder: Int

    /// Activity level based on recent notes and messages
    /// - Note: Determines animation speed in goal views
    var activityLevel: ActivityLevel

    /// Total notes count for this goal
    /// - Note: From backend, accurate regardless of pagination
    var notesCount: Int

    /// Active tasks count (pending, active, paused)
    /// - Note: From backend, excludes completed/cancelled tasks
    var tasksCount: Int

    /// Recurring check-in schedule (daily, weekdays, weekly)
    /// - Note: Nil if no recurring schedule is set
    var checkInSchedule: CheckInSchedule?

    /// UI-only: True when goal is being saved to server
    /// - Note: Not sent to backend - local UI state only
    var isSyncing: Bool = false

    // MARK: - Initializer

    /// Creates a new goal instance
    ///
    /// - Note: All parameters except id, title, and status have defaults
    init(
        id: String,
        title: String,
        description: String? = nil,
        status: Status,
        accentColor: String? = nil,
        agentInstructions: String? = nil,
        enabledMcpServers: [String]? = nil,
        activeMcpServersCount: Int? = nil,
        learnings: [[String: String]]? = nil,
        runtimeState: [String: Any]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        displayOrder: Int = 0,
        activityLevel: ActivityLevel = .moderate,
        notesCount: Int = 0,
        tasksCount: Int = 0,
        checkInSchedule: CheckInSchedule? = nil,
        isSyncing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.accentColor = accentColor
        self.agentInstructions = agentInstructions
        self.enabledMcpServers = enabledMcpServers
        self.activeMcpServersCount = activeMcpServersCount
        self.learnings = learnings
        self.runtimeState = runtimeState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displayOrder = displayOrder
        self.activityLevel = activityLevel
        self.notesCount = notesCount
        self.tasksCount = tasksCount
        self.checkInSchedule = checkInSchedule
        self.isSyncing = isSyncing
    }

    // MARK: - Nested Types

    /// Goal status lifecycle states
    enum Status: String, CaseIterable, Codable {
        /// Goal is waiting to be started
        case waiting

        /// Goal is actively being worked on
        case working

        /// Goal is archived (completed or abandoned)
        case archived

        /// User-facing display name
        var displayName: String {
            switch self {
            case .waiting: return "Not Started"
            case .working: return "In Progress"
            case .archived: return "Archived"
            }
        }
    }

    /// Activity level based on recent notes and messages
    enum ActivityLevel: String, Codable, CaseIterable {
        case high
        case moderate
        case low

        /// Animation speed multiplier for sine wave animation
        /// Higher activity = faster, more energetic animation
        var animationSpeed: Double {
            switch self {
            case .high: return 1.5
            case .moderate: return 1.0
            case .low: return 0.6
            }
        }
    }

    /// Check-in information extracted from runtime state
    ///
    /// Represents a scheduled check-in for the goal, where the agent
    /// follows up on progress and updates.
    struct CheckInInfo: Equatable, Sendable {
        /// When the check-in is scheduled for
        let scheduledFor: Date

        /// The intent/purpose of the check-in
        let intent: String

        /// Type of check-in: "scheduled" for recurring, "follow_up" for one-time
        let type: String?

        init(scheduledFor: Date, intent: String, type: String? = nil) {
            self.scheduledFor = scheduledFor
            self.intent = intent
            self.type = type
        }

        static func == (lhs: CheckInInfo, rhs: CheckInInfo) -> Bool {
            return lhs.scheduledFor == rhs.scheduledFor && lhs.intent == rhs.intent
        }
    }

    /// Recurring check-in schedule configuration
    struct CheckInSchedule: Equatable, Sendable, Codable {
        /// Frequency: daily, weekdays, weekly, or none
        let frequency: String?

        /// Time in 24-hour format: "09:00", "14:30"
        let time: String?

        /// For weekly: day of week (monday, tuesday, etc.)
        let dayOfWeek: String?

        /// Purpose of the check-in
        let intent: String?

        /// Human-readable description of the schedule
        var displayText: String? {
            guard let freq = frequency, freq != "none", let time = time else { return nil }

            let timeDisplay = formatTime(time)

            switch freq {
            case "daily":
                return "Daily at \(timeDisplay)"
            case "weekdays":
                return "Weekdays at \(timeDisplay)"
            case "weekly":
                if let day = dayOfWeek {
                    return "\(day.capitalized)s at \(timeDisplay)"
                }
                return "Weekly at \(timeDisplay)"
            default:
                return nil
            }
        }

        private func formatTime(_ time24: String) -> String {
            let parts = time24.split(separator: ":")
            guard parts.count >= 2,
                  let hour = Int(parts[0]),
                  let minutes = Int(parts[1]) else { return time24 }

            let meridiem = hour >= 12 ? "pm" : "am"
            let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

            if minutes == 0 {
                return "\(displayHour)\(meridiem)"
            } else {
                return "\(displayHour):\(String(format: "%02d", minutes))\(meridiem)"
            }
        }
    }

    // MARK: - Computed Properties

    /// Number of enabled MCP servers that are actually available
    /// - Returns: Backend-validated count if available, otherwise raw count
    /// - Note: Uses activeMcpServersCount from backend which filters out disconnected/disabled servers
    var enabledServersCount: Int {
        // Prefer backend-validated count (filters out disconnected servers)
        if let activeCount = activeMcpServersCount {
            return activeCount
        }
        // Fallback to raw count (for optimistic/local goals)
        return enabledMcpServers?.count ?? 0
    }

    /// Next scheduled check-in from recurring schedule
    ///
    /// Returns the next occurrence of the recurring schedule (daily, weekly, etc.)
    /// This is separate from follow-ups which are one-time contextual check-ins.
    var scheduledCheckIn: CheckInInfo? {
        guard let state = runtimeState,
              let scheduled = state["scheduled_check_in"] as? [String: Any],
              let scheduledForStr = scheduled["scheduled_for"] as? String,
              let intent = scheduled["intent"] as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        guard let scheduledFor = formatter.date(from: scheduledForStr) else { return nil }

        return CheckInInfo(scheduledFor: scheduledFor, intent: intent, type: "scheduled")
    }

    /// Next follow-up check-in (one-time contextual)
    ///
    /// Returns the next follow-up if one is scheduled. Follow-ups are one-time
    /// check-ins created in response to user actions or agent decisions.
    var nextFollowUp: CheckInInfo? {
        guard let state = runtimeState else { return nil }

        let formatter = ISO8601DateFormatter()

        // Check next_follow_up
        if let followUp = state["next_follow_up"] as? [String: Any],
           let scheduledForStr = followUp["scheduled_for"] as? String,
           let intent = followUp["intent"] as? String,
           let scheduledFor = formatter.date(from: scheduledForStr) {
            return CheckInInfo(scheduledFor: scheduledFor, intent: intent, type: "follow_up")
        }

        // Legacy support: check old check_ins structure
        if let checkIns = state["check_ins"] as? [String: Any],
           let shortTerm = checkIns["short_term"] as? [String: Any],
           let scheduledForStr = shortTerm["scheduled_for"] as? String,
           let intent = shortTerm["intent"] as? String,
           let scheduledFor = formatter.date(from: scheduledForStr) {
            return CheckInInfo(scheduledFor: scheduledFor, intent: intent, type: "follow_up")
        }

        return nil
    }

    /// Next check-in information (earliest of scheduled or follow-up)
    ///
    /// Convenience property that returns whichever check-in is coming up next.
    /// Use `scheduledCheckIn` and `nextFollowUp` to access them separately.
    var nextCheckIn: CheckInInfo? {
        let candidates = [scheduledCheckIn, nextFollowUp].compactMap { $0 }
        return candidates.min { $0.scheduledFor < $1.scheduledFor }
    }
}

// MARK: - Codable Conformance

extension Goal {
    /// Coding keys for Codable implementation
    /// - Note: runtimeState is intentionally excluded (non-Codable type)
    enum CodingKeys: String, CodingKey {
        case id, title, description, status, accentColor, agentInstructions
        case enabledMcpServers, activeMcpServersCount, learnings, createdAt, updatedAt, displayOrder
        case activityLevel, notesCount, tasksCount, checkInSchedule, isSyncing
        // runtimeState excluded - can't encode [String: Any]
    }

    /// Custom encoding that excludes runtimeState
    ///
    /// - Note: Required for App Group persistence via UserDefaults
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(accentColor, forKey: .accentColor)
        try container.encodeIfPresent(agentInstructions, forKey: .agentInstructions)
        try container.encodeIfPresent(enabledMcpServers, forKey: .enabledMcpServers)
        try container.encodeIfPresent(activeMcpServersCount, forKey: .activeMcpServersCount)
        try container.encodeIfPresent(learnings, forKey: .learnings)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(displayOrder, forKey: .displayOrder)
        try container.encode(activityLevel, forKey: .activityLevel)
        try container.encode(notesCount, forKey: .notesCount)
        try container.encode(tasksCount, forKey: .tasksCount)
        try container.encodeIfPresent(checkInSchedule, forKey: .checkInSchedule)
        try container.encode(isSyncing, forKey: .isSyncing)
    }

    /// Custom decoding that sets runtimeState to nil
    ///
    /// - Note: runtimeState will always be nil when decoded from persistence
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decode(Status.self, forKey: .status)
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)
        agentInstructions = try container.decodeIfPresent(String.self, forKey: .agentInstructions)
        enabledMcpServers = try container.decodeIfPresent([String].self, forKey: .enabledMcpServers)
        activeMcpServersCount = try container.decodeIfPresent(Int.self, forKey: .activeMcpServersCount)
        learnings = try container.decodeIfPresent([[String: String]].self, forKey: .learnings)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder) ?? 0
        activityLevel = try container.decodeIfPresent(ActivityLevel.self, forKey: .activityLevel) ?? .moderate
        notesCount = try container.decodeIfPresent(Int.self, forKey: .notesCount) ?? 0
        tasksCount = try container.decodeIfPresent(Int.self, forKey: .tasksCount) ?? 0
        checkInSchedule = try container.decodeIfPresent(CheckInSchedule.self, forKey: .checkInSchedule)
        isSyncing = try container.decode(Bool.self, forKey: .isSyncing)
        runtimeState = nil  // Always nil when decoded from persistence
    }
}

// MARK: - API Conversion

extension Goal {
    /// Converts API response model to domain model
    ///
    /// Transforms backend representation (snake_case, string dates, AnyDecodable)
    /// into Swift-idiomatic domain model (camelCase, Date objects, type-safe).
    ///
    /// - Parameter resource: GoalResource from backend API
    /// - Returns: Domain model ready for app use
    ///
    /// **Transformations:**
    /// - ISO8601 strings → Date objects
    /// - status string → Status enum (defaults to .waiting if unknown)
    /// - runtime_state AnyDecodable → [String: Any] dictionary
    /// - snake_case → camelCase property names
    static func from(resource: GoalResource) -> Goal {
        // Parse ISO8601 date strings to Date objects
        let created = DateHelpers.parseISO8601(resource.attributes.created_at)
        let updated = DateHelpers.parseISO8601(resource.attributes.updated_at)

        // Convert status string to enum, fallback to .waiting for unknown values
        let statusEnum = Status(rawValue: resource.attributes.status) ?? .waiting

        // Convert activity_level string to enum, fallback to .moderate for unknown values
        let activityLevelEnum = ActivityLevel(rawValue: resource.attributes.activity_level ?? "moderate") ?? .moderate

        // Extract runtime_state from AnyDecodable wrapper
        var runtimeState: [String: Any]? = nil
        if let anyValue = resource.attributes.runtime_state?.value {
            runtimeState = anyValue as? [String: Any]
        }

        // Convert check_in_schedule resource to domain model
        var checkInSchedule: CheckInSchedule? = nil
        if let scheduleResource = resource.attributes.check_in_schedule {
            checkInSchedule = CheckInSchedule(
                frequency: scheduleResource.frequency,
                time: scheduleResource.time,
                dayOfWeek: scheduleResource.day_of_week,
                intent: scheduleResource.intent
            )
        }

        return Goal(
            id: resource.id,
            title: resource.attributes.title,
            description: resource.attributes.description,
            status: statusEnum,
            accentColor: resource.attributes.accent_color,
            agentInstructions: resource.attributes.agent_instructions,
            enabledMcpServers: resource.attributes.enabled_mcp_servers,
            activeMcpServersCount: resource.attributes.active_mcp_servers_count,
            learnings: resource.attributes.learnings,
            runtimeState: runtimeState,
            createdAt: created,
            updatedAt: updated,
            displayOrder: resource.attributes.display_order ?? 0,
            activityLevel: activityLevelEnum,
            notesCount: resource.attributes.notes_count ?? 0,
            tasksCount: resource.attributes.tasks_count ?? 0,
            checkInSchedule: checkInSchedule
            // isSyncing defaults to false
        )
    }

}

// MARK: - Equatable & Hashable

extension Goal: Equatable, Hashable {
    /// Identity-based equality (same ID = same goal)
    ///
    /// - Note: Only compares IDs, not content
    /// - Rationale: Goals are entities with identity, not value objects
    static func == (lhs: Goal, rhs: Goal) -> Bool {
        return lhs.id == rhs.id
    }

    /// Identity-based hashing (hash ID only)
    ///
    /// - Note: Consistent with identity-based equality
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Supporting Models

/// Preview data for goal creation wizard
///
/// Used to pass proposed goal data from chat-based goal creation
/// to the goal form view for final editing before submission.
///
/// **Usage:**
/// ```swift
/// let preview = GoalDataPreview(
///     title: "Learn Swift",
///     description: "Master iOS development",
///     agentInstructions: "Help me learn SwiftUI",
///     learnings: ["Started with basics"],
///     enabledMcpServers: ["github"]
/// )
/// ```
struct GoalDataPreview: Identifiable, Hashable, Sendable {
    /// Unique identifier (local only - not from backend)
    var id = UUID()

    /// Proposed goal title
    var title: String

    /// Proposed goal description
    var description: String

    /// Proposed agent instructions
    var agentInstructions: String

    /// Proposed initial learnings
    var learnings: [String]

    /// Proposed enabled MCP servers
    var enabledMcpServers: [String]
}
