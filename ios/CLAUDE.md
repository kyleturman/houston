# iOS Development Guide (Swift)

**Prerequisites:** Read `../CLAUDE.md` first.

This guide covers Swift concurrency, APIClient, color system, ViewModels, real-time updates, tools, SSE, and build validation.

---

## 📋 Quick Reference

### Most Common Tasks

**Adding a View?**
1. Use `@Observable` + `@MainActor` for ViewModels
2. Colors: `Color.foreground["000"]`, `Color.background["100"]`
3. API calls: `try await client.getCurrentFeed()`
4. Run `make ios-check` before commit

**Real-Time Updates?**
1. Inject `StateManager` via `@Environment`
2. Subscribe to publishers (`noteCreatedPublisher`, etc.)
3. Trigger `load()` on ViewModel when event matches your context

**Adding SSE Event?**
1. Add to `EventType` enum in `SSEClient.swift`
2. Add publisher in `StateManager.swift` (if global lifecycle event)
3. Handle in `handleEvent()` switch

**API Client?**
1. Always use `APIClient` - never manual `URLRequest`
2. Pass token providers at init
3. Handles auth, decoding, errors automatically

---

## 🚀 Three Critical Rules

1. **API Calls** - ALWAYS use `APIClient`, NEVER manual `URLRequest`
2. **Colors** - ALWAYS use `Color.foreground["000"]`, NEVER hardcoded colors
3. **Build** - MUST run `make ios-check` after any changes

---

## 🐛 Debugging

### When Something Breaks After Refactoring

1. **Git diff first** - See exactly what changed:
   ```bash
   git diff <last-working-commit> HEAD -- ios/Sources/path/to/file.swift
   ```

2. **Verify types exist** - Renamed types may not be in scope:
   ```swift
   // ❌ WRONG - AnyCodable doesn't exist
   let dict = value as? [String: AnyCodable]

   // ✅ CORRECT - Use fully qualified type
   let dict = value as? [String: APIClient.AnyDecodable]
   ```

3. **Trace the full flow** - Follow data from backend → iOS:
   - Backend tests: Verify output works and matches what we're looking for in client
   - Code: Understand full code flow first! Trace parsing → storage → rendering
   - Logs: Check actual types and values received in app but use logging as last resort

---

## 📐 Code Patterns

**YAGNI:** Use simplest pattern (e.g., `ToastManager.shared`). Add abstraction when 3+ similar implementations.

**File naming:** ViewModels/Views get suffixes, models don't. Extensions use `+` prefix.

**File size:** Extract when >300 lines or distinct responsibility. Keep helpers <50 lines together.

**Immutability:** Prefer `let` over `var`. Create new instances instead of mutating.

**Views:** Break into components when >100 lines.

---

## ⚡ Swift 6+ Concurrency

**NOTE:** Project targets iOS 18.6 and Swift 6+ (post-January 2025). Use web search for latest best practices.

**Core patterns:**
```swift
// ViewModels: @MainActor + @Observable (NOT @Published)
@MainActor
@Observable
final class MyViewModel {
    var items: [Item] = []

    @MainActor isolated deinit { sse?.stop() }  // Safe cleanup
}

// Sendable: Add to protocols, @unchecked for classes (restate in subclasses)
protocol MyProtocol: Sendable { }
final class MyClass: @unchecked Sendable { }

// Closures: Use @Sendable for concurrency boundaries
typealias Callback = @Sendable (Result) -> Void

// Timer/delegates: Wrap main actor calls
Timer.scheduledTimer(...) { _ in Task { @MainActor in updateUI() } }
```

**Modern SwiftUI:** Use `.onChange(of:) { _, new in }` (iOS 17+), `.navigationDestination` (iOS 16+), `let` for static properties.

**UIKit/System Delegates:** For `@MainActor` classes conforming to non-MainActor protocols (e.g., `UNUserNotificationCenterDelegate`):
1. Mark protocol methods as `nonisolated` to satisfy the protocol
2. Dispatch to main actor via `Task { @MainActor in }` for UI work
3. Use completion handler versions (not async) - async causes UIKit assertion failures during cold launch

### ⚠️ CRITICAL: Main Thread Blocking & Swift 6.2 Best Practices

**NEVER block main thread during view initialization or data loading. Use Swift 6.2+ patterns.**

**Problem Pattern (WRONG):**
```swift
// ❌ WRONG - Blocks UI until load completes
.task {
    await viewModel.load()  // Waits! UI hangs
}

// ❌ OLD PATTERN - Task.detached loses priority, causes Sendable warnings
Task.detached { [weak self] in  // Don't use this!
    let data = try await client.fetchData()
    await MainActor.run { self?.items = data }
}
```

**Correct Pattern (Swift 6.2):**
```swift
// ✅ CORRECT - Non-blocking .task modifier
.task {
    Task { await viewModel.load() }  // Returns instantly
}

// ✅ MODERN - nonisolated async (best practice)
@MainActor func load() async {
    loading = true
    errorMessage = nil
    guard let client = makeClient() else {
        errorMessage = "Failed to create client"
        loading = false
        return
    }
    await loadDataInBackground(client: client)  // Compiler runs off MainActor
    loading = false
}

nonisolated private func loadDataInBackground(client: APIClient) async {
    // Automatically runs on background thread, no Task.detached needed
    do {
        let data = try await client.fetchData()
        await MainActor.run { self.items = data }
    } catch {
        await MainActor.run { self.errorMessage = error.localizedDescription }
    }
}
```

**Why This Matters:**
- `@MainActor` ViewModels run ALL code on main thread
- Even `async/await` blocks if called from `@MainActor` context
- Apple's rule: No work >100ms on main thread
- `nonisolated async` methods automatically run off MainActor (compiler magic)

**Key Benefits of nonisolated async:**
- ✅ No Task.detached (avoids priority loss, Sendable warnings)
- ✅ No [weak self] closures needed
- ✅ Compiler automatically runs on background thread
- ✅ Cleaner code, better performance

**Best Practice:**
1. Views ALWAYS open instantly (non-blocking .task)
2. Show loading state immediately
3. Use nonisolated async for background work
4. Explicit MainActor.run() for UI updates

---

## 🌐 API Client Pattern

**Use `APIClient` for ALL API calls.**

### Correct Usage
```swift
// CORRECT - APIClient handles auth, decoding, errors
let client = APIClient(
    baseURL: baseURL,
    deviceTokenProvider: { self.sessionManager.deviceToken },
    userTokenProvider: { self.sessionManager.userToken }
)
let feed = try await client.getCurrentFeed()
```

### Wrong Usage
```swift
// WRONG - Manual URLRequest
var request = URLRequest(url: url)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
let (data, _) = try await URLSession.shared.data(for: request)
```

**Files:**
```
ios/Sources/Core/Data/APIClient.swift                  # Main client
ios/Sources/Core/Models/API/**/*.swift                # API models (match backend serializers)
ios/Sources/Core/Models/**/*.swift                     # Domain models
```

---

## 🎨 Color System

**Use the theme system - NEVER hardcoded colors.**

### Usage Pattern
```swift
// CORRECT - Theme-aware colors
Text("Title").foregroundColor(Color.foreground["000"])
Rectangle().fill(Color.background["100"])
Divider().background(Color.border["000"])

// WRONG - Hardcoded colors
Text("Title").foregroundColor(.black)
Rectangle().fill(.white)
```

### Available Color Sets
```swift
Color.foreground["000"]  // Primary text
Color.foreground["100"]  // Secondary text
Color.background["000"]  // Primary background
Color.background["100"]  // Secondary background
Color.border["000"]      // Primary borders
```

### Files
```
ios/Resources/colors.json                         # Color definitions
ios/Sources/Core/Styles/ColorSystem.swift          # Parsing
ios/Sources/Core/Styles/ThemeManager.swift         # Theme switching
ios/Sources/Core/Styles/ColorExtensions.swift      # Clean syntax
```

---

## 🔧 Tool System

**Self-contained tools** (data + UI in one file). Conform to `ToolHandler` protocol. Backend auto-loads MCP tools; `GeneralTool.swift` handles unknown tools automatically. Add custom views only if needed.

Files: `ios/Sources/Features/Chat/Tools/{CreateTaskTool,CreateNoteTool,SearchTool,GeneralTool}.swift`

---

## 📦 ViewModels

**Use protocol-based ViewModels:** `BaseViewModel` (common state) + `ResourceViewModel` (list views).

```swift
@MainActor
@Observable
final class NotesViewModel: ResourceViewModel {
    var items: [Note] = []
    var loading = false

    // ✅ Returns immediately, loads in background
    func load() async {
        loading = true
        Task {
            defer { await MainActor.run { loading = false } }
            // ... network request
        }
    }
}
```

**IMPORTANT:** See "Main Thread Blocking" section above - `load()` methods must NOT block UI.

Files: `ios/Sources/Core/ViewModels/{BaseViewModel,ResourceViewModel}.swift`

---

## 🔄 Real-Time Updates (StateManager)

**Global SSE for lifecycle events** - auto-handles backgrounding.

```swift
@Environment(StateManager.self) var stateManager

var body: some View {
    List(notes) { note in NoteRow(note: note) }
        .onReceive(stateManager.noteCreatedPublisher) { event in
            if event.goal_id == goalId {
                Task { await notesVM.load() }
            }
        }
}
```

**Publishers:**
- Notes: `noteCreatedPublisher`, `noteUpdatedPublisher`, `noteDeletedPublisher`
- Tasks: `taskCreatedPublisher`, `taskUpdatedPublisher`, `taskCompletedPublisher`
- Goals: `goalCreatedPublisher`, `goalUpdatedPublisher`, `goalArchivedPublisher`

**File:** `ios/Sources/Core/Networking/StateManager.swift`

---

## 💾 Save Operations (SaveCoordinator)

**Consistent save feedback** - optimistic or blocking.

```swift
// Optimistic (dismiss immediately)
await SaveCoordinator.optimisticSave(
    loadingMessage: "Saving...",
    successMessage: "Saved",
    operation: { try await client.createNote(...) }
)

// Blocking (wait for result)
let result = await SaveCoordinator.blockingSave(
    successMessage: "Updated",
    operation: { try await client.updateProfile(...) }
)
if case .success = result { dismiss() }
```

**File:** `ios/Sources/Core/Utils/SaveCoordinator.swift`

---

## 🔄 SSE Streaming

**Always use `authorizedStreamRequest()` helper** for SSE endpoints.

**Two types:** Agent Chat (ChatViewModel) + Global Lifecycle (StateManager)

**Events:** `tool_start/progress/completion` (agent), `note_created/updated/deleted` (lifecycle)

**Adding events:** Add to `EventType` enum in `SSEClient.swift` (CRITICAL - missing = `.unknown`). For global events, also add publisher in `StateManager.swift`.

---

## 📱 ChatViewModel State

**Keep alive on sheet close** (preserves messages). Pre-create before showing sheet.

---

## 🍎 Build Validation

**Run `make ios-check` before every commit** - catches syntax errors early. DO NOT use xcodebuild directly for checking builds, use the make commands here instead. You can use xcode mcp tools for exploring the simulator and such, but always use these commands for build testing:

```bash
make ios-check               # Quick (quiet)
make ios-check-clean         # Clean + validate
make ios-check-verbose       # Detailed output
```

**Requirements:** Full Xcode at `/Applications/Xcode.app/Contents/Developer`

**Artifacts:** `ios/build/` (output), `ios/build/build_*.log` (logs)

---

## 🗂️ Key Files

**Use Glob to find files:**
```bash
# Core infrastructure
ios/Sources/Core/Data/APIClient.swift                 # APIClient
ios/Sources/Core/Networking/SSEClient.swift           # SSE streaming
ios/Sources/Core/Styles/**/*.swift                    # Theme, Colors
ios/Sources/Core/ViewModels/**/*.swift                # ViewModels (Base, Resource)
ios/Sources/Core/Networking/StateManager.swift        # Global SSE
ios/Sources/Core/Utils/SaveCoordinator.swift          # Saving form data

# Feature code
ios/Sources/Features/**/*.swift                       # All features
ios/Sources/Features/Chat/Tools/**/*.swift            # Tool UI components

# Models (Two layers)
ios/Sources/Core/Models/API/**/*.swift                # API models (match backend)
ios/Sources/Core/Models/**/*.swift                    # Domain models

# Resources
ios/Resources/colors.json                             # Color definitions
```

**Critical to read:**
- `Core/Data/APIClient.swift` - All API calls go through here
- `Core/Styles/ColorSystem.swift` - Theme system implementation
- `Core/Networking/StateManager.swift` - Real-time updates
- `Core/Models/API/` - Must match backend serializers exactly

---

## Checklist

1. **APIClient** - Always use, never manual `URLRequest`
2. **Colors** - `Color.foreground["000"]`, never hardcoded
3. **Concurrency** - `@Observable` + `@MainActor`, `isolated deinit`
4. **Main Thread** - NEVER block during view init/load (spawn Task, don't await in .task)
5. **ViewModels** - `ResourceViewModel` for lists, `BaseViewModel` for others
6. **Real-time** - `StateManager` publishers
7. **Build** - `make ios-check` before commit
8. **SSE** - `authorizedStreamRequest()` helper
9. **ChatViewModel** - Keep alive on close
10. **Sendable** - Add to protocols, `@unchecked Sendable` to classes
11. **Closures** - `@Sendable` for concurrency, `@Sendable @MainActor` for UI
12. **Timer/Delegates** - Mark delegate methods `nonisolated` when class is `@MainActor`; wrap work in `Task { @MainActor in }`
13. **SwiftUI** - iOS 17+ `onChange(of:) { _, new in }`
14. **Immutability** - Prefer `let` over `var`
15. **Web search** - iOS 18.6/Swift 6 released after your training - always verify current best practices
16. **DRY** - Don't repeat the same code over and over, look for opportunities to consolidate
17. **YAGNI** - Don't add abstractions until 3+ similar cases
18. **File naming** - ViewModels end in `ViewModel.swift`, Views in `View.swift`
19. **Two-layer models** - API models match serializers, domain models for business logic
20. **SaveCoordinator** - Use `SaveCoordinator.optimisticSave` for optimistic saves, `SaveCoordinator.blockingSave` for blocking saves

**Related:** `../CLAUDE.md` (root) | `../backend/CLAUDE.md` (backend)
