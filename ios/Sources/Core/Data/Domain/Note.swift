import Foundation

// MARK: - Note Domain Model
//
// Purpose:
//   Represents a note created by users or agents, with optional images,
//   goal associations, and flexible metadata for web summaries and processing.
//
// API Mapping:
//   Source: NoteResource (Core/Models/API/NoteAPI.swift)
//   Conversion: Note.from(resource:)
//   Key transforms:
//     - created_at (String?) → createdAt (Date?)
//     - source (String) → source (Source enum)
//     - goal_id (String?) → goalId (String?)
//     - metadata (AnyCodable?) → metadata ([String: AnyCodable]?)
//     - images extracted from metadata["images"] → images ([NoteImage]?)
//
// Usage:
//   - Note list/detail views (NotesView, NoteDetailSheetView)
//   - Agent note creation (CreateNoteTool)
//   - Goal notes integration (GoalNotesViewModel)
//
// Persistence:
//   - Not Codable (no App Group sync needed)
//   - metadata uses AnyCodable for flexible backend data
//   - Custom Equatable (excludes metadata)
//
// Thread Safety:
//   - Struct (value type) safe for concurrent access
//   - Immutable properties (let) enforce read-only semantics

/// Image attachment for a note
///
/// Images are stored in metadata and extracted during API conversion.
/// Used for notes with visual content like screenshots or diagrams.
///
/// **Example:**
/// ```swift
/// let image = NoteImage(
///     url: "https://example.com/image.jpg",
///     alt: "Screenshot of dashboard"
/// )
/// ```
struct NoteImage: Codable, Equatable, Sendable {
    /// URL to the image resource
    let url: String

    /// Alternative text description for accessibility
    let alt: String?
}

/// User or agent-created note with optional attachments
///
/// Notes are text content that can be associated with goals, include images,
/// and have flexible metadata for web content, processing state, etc.
///
/// **Lifecycle:**
/// 1. Backend returns NoteResource via JSON:API
/// 2. Decoded to NoteResource in API layer
/// 3. Converted to Note via Note.from(resource:)
/// 4. Used in views and ViewModels
///
/// **Concurrency:**
/// - Swift 6: Conforms to @unchecked Sendable for safe concurrent access
/// - metadata contains non-Sendable AnyCodable but is immutable after creation
/// - @unchecked is safe because: structs are value types, metadata never mutated after init
///
/// **Example:**
/// ```swift
/// let resource: NoteResource = /* from API */
/// let note = Note.from(resource: resource)
///
/// // Access properties
/// print(note.content)
/// if let url = note.sourceURL {
///     print("Web source: \(url)")
/// }
/// ```
struct Note: Identifiable, @unchecked Sendable {
    // MARK: - Properties

    /// Unique identifier from backend
    let id: String

    /// Optional note title
    /// - Note: May be nil for quick notes without titles
    let title: String?

    /// Main text content of the note
    /// - Note: May be nil for URL-only notes (content stored in metadata)
    let content: String?

    /// Origin of the note (user, agent, import, system)
    let source: Source

    /// When the note was created
    let createdAt: Date?

    /// Open Graph preview image for link notes (used in cards)
    /// - Note: Separate from content images, stored as metadata["og_image"]
    let ogImage: NoteImage?

    /// Content images from article (filtered, no logos/icons)
    /// - Note: Images stored as metadata["images"] in backend
    let images: [NoteImage]?

    /// Associated goal ID if note belongs to a goal
    /// - Note: String ID per JSON:API best practice
    let goalId: String?

    /// Flexible metadata from backend
    /// - Note: Contains processing_state, web_summary, source_url, images
    /// - Format: Dictionary with AnyCodable values for type flexibility
    let metadata: [String: AnyCodable]?

    // MARK: - Nested Types

    /// Note source/origin type
    ///
    /// Indicates who or what created the note for filtering and display.
    enum Source: String, Codable {
        /// User-created note
        case user

        /// Agent-created note (via tools)
        case agent

        /// Imported from external source
        case import_

        /// System-generated note
        case system

        /// Creates source from backend string
        ///
        /// - Parameter raw: Backend source string (handles "import" special case)
        /// - Note: Backend uses "import" but Swift enum uses "import_" (reserved word)
        init(raw: String) {
            if raw == "import" {
                self = .import_
            } else {
                self = Source(rawValue: raw) ?? .user
            }
        }

        /// User-facing display name
        var display: String {
            switch self {
            case .user: return "User"
            case .agent: return "Agent"
            case .import_: return "Import"
            case .system: return "System"
            }
        }
    }

    // MARK: - Computed Properties

    /// Processing state for web content notes
    ///
    /// Indicates backend processing status for URL-based notes.
    ///
    /// **Possible values:**
    /// - "pending": Waiting to process
    /// - "processing": Currently processing
    /// - "completed": Processing finished
    /// - "failed": Processing error
    ///
    /// - Returns: Processing state string or nil if not applicable
    var processingState: String? {
        metadata?["processing_state"]?.value as? String
    }

    /// AI-generated summary for web content
    ///
    /// For notes created from URLs, contains LLM-generated summary
    /// of the web page content.
    ///
    /// - Returns: Summary text or nil if not a web note
    var webSummary: String? {
        metadata?["web_summary"]?.value as? String
    }

    /// Original URL for web content notes
    ///
    /// For notes imported from URLs, contains the source URL.
    ///
    /// - Returns: Source URL string or nil if not a web note
    var sourceURL: String? {
        metadata?["source_url"]?.value as? String
    }
}

// MARK: - API Conversion

extension Note {
    /// Converts API response model to domain model
    ///
    /// Transforms backend representation into Swift-idiomatic domain model.
    /// Extracts images from metadata and parses ISO8601 dates.
    ///
    /// - Parameter resource: NoteResource from backend API
    /// - Returns: Domain model ready for app use
    ///
    /// **Transformations:**
    /// - ISO8601 string → Date object
    /// - source string → Source enum (handles "import" special case)
    /// - metadata["images"] → images array of NoteImage
    /// - snake_case → camelCase property names
    ///
    /// **Example:**
    /// ```swift
    /// let resource = try decoder.decode(NoteResource.self, from: data)
    /// let note = Note.from(resource: resource)
    /// print(note.images?.count ?? 0)
    /// ```
    static func from(resource: NoteResource) -> Note {
        let attrs = resource.attributes

        // Parse ISO8601 date string to Date object
        let created = DateHelpers.parseISO8601(attrs.created_at)

        // Extract OG image from metadata["og_image"]
        var ogImage: NoteImage? = nil
        if let metadata = attrs.metadata,
           let ogImageData = metadata["og_image"]?.value as? [String: Any],
           let url = ogImageData["url"] as? String {
            let alt = ogImageData["alt"] as? String
            ogImage = NoteImage(url: url, alt: alt)
        }

        // Extract content images from metadata["images"] array
        var images: [NoteImage]? = nil
        if let metadata = attrs.metadata,
           let imagesData = metadata["images"]?.value as? [[String: Any]] {
            images = imagesData.compactMap { dict -> NoteImage? in
                guard let url = dict["url"] as? String else { return nil }
                let alt = dict["alt"] as? String
                return NoteImage(url: url, alt: alt)
            }
        }

        return Note(
            id: resource.id,
            title: attrs.title,
            content: attrs.content,
            source: Source(raw: attrs.source),
            createdAt: created,
            ogImage: ogImage,
            images: images,
            goalId: attrs.goal_id,
            metadata: attrs.metadata
        )
    }
}

// MARK: - Equatable

/// Custom Equatable implementation
///
/// Notes are equal if core properties match. Metadata is intentionally
/// excluded as it contains AnyCodable (non-Equatable) and is considered
/// supplementary data that doesn't affect note identity.
///
/// **Rationale:**
/// - metadata contains flexible backend data (processing state, etc.)
/// - metadata changes don't represent a "different note"
/// - Core properties define note identity
extension Note: Equatable {
    static func == (lhs: Note, rhs: Note) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.content == rhs.content &&
               lhs.source == rhs.source &&
               lhs.createdAt == rhs.createdAt &&
               lhs.ogImage == rhs.ogImage &&
               lhs.images == rhs.images &&
               lhs.goalId == rhs.goalId
        // metadata intentionally excluded - contains non-Equatable AnyCodable
    }
}
