# Models Architecture

This directory contains the app's data models organized into two layers: **API** (backend contract) and **Domain** (Swift-idiomatic).

## Directory Structure

```
Data/
├── APIClient.swift              # HTTP endpoints (all in one file with MARK sections)
├── API/
│   ├── Infrastructure/          # Shared networking concerns
│   │   ├── NetworkingProtocols.swift   # URLSessionProtocol for testability
│   │   ├── ResponseValidation.swift    # HTTP response validation helpers
│   │   ├── APILogger.swift             # Centralized logging (toggle-able)
│   │   └── APICacheManager.swift       # Encrypted cache management
│   ├── Models/                  # All API response/request types
│   │   ├── GoalAPI.swift
│   │   ├── NoteAPI.swift
│   │   ├── TaskAPI.swift
│   │   ├── AgentActivityAPI.swift
│   │   ├── AgentHistoryAPI.swift
│   │   ├── ThreadMessageAPI.swift
│   │   ├── MCPServerAPI.swift
│   │   ├── AuthResponseAPI.swift
│   │   └── UserAgentAPI.swift
│   ├── DecodingHelpers.swift    # AnyDecodable, AnyCodable, JSONValue
│   └── JSONAPIWrappers.swift    # JSON:API response wrappers
└── Domain/                      # Swift-idiomatic app models
    ├── Goal.swift
    ├── Note.swift
    └── ...
```

## Why Two Layers?

**API Layer** (`API/`) - Matches backend exactly:
- Decodes JSON:API responses from Rails backend
- Uses snake_case (e.g., `goal_id`, `created_at`)
- Keeps dates as strings, IDs as strings
- Shared with App Extensions and Shortcuts

**Domain Layer** (`Domain/`) - Swift-friendly for the app:
- Converts to camelCase (e.g., `goalId`, `createdAt`)
- Parses dates to `Date`, status strings to enums
- Contains business logic and computed properties
- Used throughout ViewModels and Views

## Quick Reference

| Question | Answer |
|----------|--------|
| "Where are HTTP endpoints?" | `APIClient.swift` - use MARK sections or search |
| "Where is caching logic?" | `API/Infrastructure/APICacheManager.swift` |
| "Where are API response types?" | `API/Models/` - all in one place |
| "Where are domain models?" | `Domain/` - Swift-idiomatic types |
| "Where are JSON helpers?" | `API/` root - DecodingHelpers, JSONAPIWrappers |

## Data Flow

```
Backend (Rails)
    ↓ JSON:API
API Models          (GoalResource with snake_case)
    ↓ .from(resource:)
Domain Models       (Goal with camelCase, Date, enums)
    ↓
ViewModels & Views
```

## Schema Change Process

When backend adds/changes a field (e.g., `archived_at`):

**1. Update API Layer** (`API/Models/GoalAPI.swift`):
```swift
struct GoalAttributes: Decodable {
    let archived_at: String?  // ← Add field (snake_case, String)
}
```

**2. Update Domain Layer** (`Domain/Goal.swift`):
```swift
struct Goal {
    var archivedAt: Date?  // ← Add property (camelCase, Date)

    static func from(resource: GoalResource) -> Goal {
        let archived = parseISO8601(resource.attributes.archived_at)
        return Goal(..., archivedAt: archived)
    }
}
```

**3. Bump Cache Version** (`APIClient.swift`):
```swift
private let cacheVersion = "2025-11-05-a"  // ← Current date
```

**4. Validate**: Run `make ios-check`

## Key Patterns

**API Models:**
- Match backend serializers exactly
- snake_case property names
- String types for dates and IDs
- Decodable only (no encoding usually)

**Domain Models:**
- camelCase property names (Swift convention)
- Parsed types (`Date`, enums, not strings)
- Computed properties for derived values
- Business logic lives here
- `static func from(resource:)` for conversion

## Common Questions

**Q: Why not just use API models directly?**
A: Domain layer provides Swift-idiomatic types and business logic.

**Q: Do I update both layers for every change?**
A: Yes - API layer matches backend, Domain layer converts it. Both are lightweight updates.

**Q: Where do I add business logic?**
A: Domain models - computed properties like `nextCheckIn`, `isRetryable`, `formattedDuration`.

**Q: What about ViewModels?**
A: They use Domain models, not API models. Domain models are the "currency" of the app.

**Q: How do extensions access these?**
A: API models are shared (Extensions can decode). Domain models are main app only.

**Q: Where do I add new API response types?**
A: In `API/Models/` - create a new file or add to the relevant existing file.
