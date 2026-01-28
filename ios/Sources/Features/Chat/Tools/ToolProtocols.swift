import Foundation
import SwiftUI

// MARK: - Core Protocols

/// Represents the status of a tool execution
enum ToolStatus: Equatable {
    case inProgress
    case success
    case failure(String?)

    init(from statusString: String) {
        switch statusString.lowercased() {
        case "in_progress", "in-progress", "running":
            self = .inProgress
        case "success", "completed", "done":
            self = .success
        case "failure", "failed", "error":
            self = .failure(nil)
        default:
            self = .inProgress
        }
    }
}

// MARK: - Tool Activity Helper

/// Helper to extract standardized tool_activity structure from metadata
/// Reduces boilerplate in tool implementations
struct ToolActivityExtractor {
    let toolActivity: [String: Any]
    let data: [String: Any]
    let status: ToolStatus

    /// Extract tool_activity and data from metadata
    /// Returns nil if tool_activity is missing (invalid structure)
    init?(metadata: [String: Any]) {
        guard let toolActivity = metadata.dictionary(for: "tool_activity") else {
            return nil
        }

        self.toolActivity = toolActivity
        self.data = toolActivity.dictionary(for: "data") ?? [:]
        self.status = ToolStatus(from: toolActivity.string(for: "status") ?? "in_progress")
    }

    /// Convenience getters for common tool_activity fields
    var displayMessage: String? {
        toolActivity.string(for: "display_message")
    }

    var errorMessage: String? {
        toolActivity.string(for: "error")
    }

    var input: [String: Any]? {
        toolActivity.dictionary(for: "input")
    }
}

/// Protocol for tool implementations that handle both data and UI
protocol ToolHandler: Identifiable, Equatable {
    /// The tool name this handler manages
    static var toolName: String { get }
    
    /// Unique identifier for this tool execution
    var id: String { get }
    
    /// Current status of the tool
    var status: ToolStatus { get set }
    
    /// Display title for the tool
    var displayTitle: String { get }
    
    /// Whether this tool should be visible to users
    var isUserFacing: Bool { get }
    
    /// Initialize from raw metadata dictionary
    init?(id: String, metadata: [String: Any])
    
    /// Update existing data with new metadata (for streaming updates)
    mutating func update(from metadata: [String: Any])

    /// Create the SwiftUI view for this tool
    @MainActor func createView(actions: ChatCellActions) -> AnyView
}

// MARK: - Type-Erased Wrapper

/// Helper box to avoid data race warnings when capturing handlers in closures
private final class HandlerBox<T: ToolHandler>: @unchecked Sendable {
    var handler: T
    init(_ handler: T) { self.handler = handler }
}

/// Type-erased wrapper for tool handlers
struct AnyToolHandler: Identifiable, Equatable {
    let id: String
    let toolName: String
    var status: ToolStatus
    let displayTitle: String
    let isUserFacing: Bool
    // Incremented whenever underlying handler updates so SwiftUI can detect changes
    private(set) var stateVersion: Int = 0

    private let _update: (inout AnyToolHandler, [String: Any]) -> Void
    private let _createView: @MainActor (ChatCellActions) -> AnyView

    init<T: ToolHandler>(_ handler: T) {
        self.id = handler.id
        self.toolName = T.toolName
        self.status = handler.status
        self.displayTitle = handler.displayTitle
        self.isUserFacing = handler.isUserFacing

        // Box the handler to avoid mutation warnings
        let box = HandlerBox(handler)

        self._update = { anyHandler, metadata in
            box.handler.update(from: metadata)
            anyHandler.status = box.handler.status
            // Bump version so Equatable changes even if status doesn't
            anyHandler.stateVersion &+= 1
        }
        self._createView = { @MainActor actions in
            box.handler.createView(actions: actions)
        }
    }

    mutating func update(from metadata: [String: Any]) {
        _update(&self, metadata)
    }

    @MainActor func createView(actions: ChatCellActions) -> AnyView {
        _createView(actions)
    }
    
    static func == (lhs: AnyToolHandler, rhs: AnyToolHandler) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.stateVersion == rhs.stateVersion
    }
}

// MARK: - Tool Registry

/// Central registry for all tool types
class ToolRegistry {
    nonisolated(unsafe) private static var toolFactories: [String: (String, [String: Any]) -> AnyToolHandler?] = [:]
    
    /// Register a tool type
    static func register<T: ToolHandler>(_ type: T.Type) {
        toolFactories[T.toolName] = { id, metadata in
            guard let handler = T(id: id, metadata: metadata) else { return nil }
            return AnyToolHandler(handler)
        }
    }
    
    /// Create tool handler from metadata
    static func createHandler(id: String, toolName: String, metadata: [String: Any]) -> AnyToolHandler? {
        return toolFactories[toolName]?(id, metadata)
    }
    
    /// Get all registered tool names
    static var registeredTools: [String] {
        Array(toolFactories.keys)
    }
}

// MARK: - Chat Cell Actions

/// Actions that can be performed from chat cells
struct ChatCellActions: Sendable {
    let onOpenTask: @Sendable @MainActor (String) -> Void
    let onOpenNote: @Sendable @MainActor (String) -> Void
    let goal: Goal?
}

// MARK: - Metadata Helpers

extension Dictionary where Key == String, Value == Any {
    /// Safely extract string value
    func string(for key: String) -> String? {
        return self[key] as? String
    }
    
    /// Safely extract int value
    func int(for key: String) -> Int? {
        return self[key] as? Int
    }
    
    /// Safely extract string from int or string
    func stringOrInt(for key: String) -> String? {
        if let string = self[key] as? String {
            return string
        }
        if let int = self[key] as? Int {
            return String(int)
        }
        return nil
    }
    
    /// Safely extract nested dictionary
    func dictionary(for key: String) -> [String: Any]? {
        return self[key] as? [String: Any]
    }
}
