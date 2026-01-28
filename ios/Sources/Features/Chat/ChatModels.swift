import Foundation

// Import existing models to avoid duplication

// MARK: - Chat message model

struct ChatMessage: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    var content: String
    let source: MessageSource
    let createdAt: Date
    var isStreaming: Bool = false
    var tool: AnyToolHandler?
    let agentHistoryId: String?

    enum MessageSource: String, CaseIterable {
        case user, agent, error
    }

    // Manual memberwise initializer
    init(id: String, content: String, source: MessageSource, createdAt: Date, isStreaming: Bool = false, tool: AnyToolHandler? = nil, agentHistoryId: String? = nil) {
        self.id = id
        self.content = content
        self.source = source
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.tool = tool
        self.agentHistoryId = agentHistoryId
    }
    
    // Manual Equatable implementation
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.source == rhs.source &&
               lhs.createdAt == rhs.createdAt &&
               lhs.isStreaming == rhs.isStreaming &&
               lhs.tool == rhs.tool &&
               lhs.agentHistoryId == rhs.agentHistoryId
    }
    
    init(from resource: ThreadMessageResource) {
        self.id = resource.id
        self.content = resource.attributes.content
        self.source = MessageSource(rawValue: resource.attributes.source) ?? .error

        print("💬 [ChatMessage] Parsing message \(resource.id):")
        print("   content: \(resource.attributes.content)")
        print("   source: \(resource.attributes.source)")

        // Parse created_at timestamp
        if let createdAtString = resource.attributes.created_at {
            let formatter = ISO8601DateFormatter()
            self.createdAt = formatter.date(from: createdAtString) ?? Date()
        } else {
            self.createdAt = Date()
        }

        // Parse agent_history_id
        self.agentHistoryId = resource.attributes.agent_history_id

        // Parse tool activity from metadata
        self.tool = nil // Default to nil

        // AnyDecodable.value for dictionaries is [String: Any], NOT [String: AnyDecodable]
        guard let metadata = resource.attributes.metadata,
              let toolActivityWrapper = metadata["tool_activity"],
              let toolActivityDict = toolActivityWrapper.value as? [String: Any],
              let toolName = toolActivityDict["name"] as? String,
              toolName != "send_message" else {
            return
        }

        // Extract activity ID (supports both String and Int)
        let activityId: String
        if let stringId = toolActivityDict["id"] as? String {
            activityId = stringId
        } else if let intId = toolActivityDict["id"] as? Int {
            activityId = String(intId)
        } else {
            activityId = UUID().uuidString
        }

        // Wrap tool_activity in metadata structure (tools expect this format)
        let metadataDict: [String: Any] = [
            "tool_activity": toolActivityDict
        ]

        // Create tool handler via factory
        self.tool = ToolFactory.createHandler(
            id: activityId,
            toolName: toolName,
            metadata: metadataDict
        )
    }
}


// MARK: - Tool Factory

class ToolFactory {
    /// Initialize the tool registry with all known tool types
    static func initializeRegistry() {
        ToolRegistry.register(CreateTaskTool.self)
        ToolRegistry.register(CreateNoteTool.self)
        ToolRegistry.register(GenerateFeedInsightsTool.self)
        // SearchTool is handled specially since it covers multiple tool names
    }
    
    /// Create tool handler from metadata
    static func createHandler(id: String, toolName: String, metadata: [String: Any]) -> AnyToolHandler? {
        // Handle search tools specially
        if SearchTool.isSearchTool(toolName) {
            if let searchTool = SearchTool.createForTool(toolName, id: id, metadata: metadata) {
                return AnyToolHandler(searchTool)
            }
        }
        
        // Try registered tools
        if let handler = ToolRegistry.createHandler(id: id, toolName: toolName, metadata: metadata) {
            return handler
        }
        
        // Fallback to general tool
        let generalTool = GeneralTool.createFallback(id: id, toolName: toolName, metadata: metadata)
        return AnyToolHandler(generalTool)
    }
}
