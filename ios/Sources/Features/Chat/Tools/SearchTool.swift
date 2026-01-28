import Foundation
import SwiftUI

// MARK: - Search Tool (Data + UI)

struct SearchTool: ToolHandler {
    static let toolName = "brave_web_search" // Primary search tool
    
    let id: String
    var status: ToolStatus
    let searchQuery: String?
    let searchResults: [SearchResult]?
    let resultsCount: Int?
    
    var displayTitle: String {
        return "Web Search"
    }
    
    var isUserFacing: Bool { true }
    
    init?(id: String, metadata: [String: Any]) {
        self.id = id

        // Extract from tool_activity (standardized backend structure)
        let toolActivity = metadata.dictionary(for: "tool_activity")
        self.status = ToolStatus(from: toolActivity?.string(for: "status") ?? "in_progress")

        // Extract search query from tool_activity.input (try both 'query' and 'q')
        let inputData = toolActivity?.dictionary(for: "input")
        self.searchQuery = inputData?.string(for: "query") ?? inputData?.string(for: "q") ?? inputData?.string(for: "instructions")

        // All tool data is in tool_activity.data (standardized)
        let toolData = toolActivity?.dictionary(for: "data")
        var results: [SearchResult]?

        // First try normalized_results (backend-processed, consistent format)
        if let normalizedResults = toolData?["normalized_results"] as? [[String: Any]] {
            results = normalizedResults.compactMap { item in
                guard let title = item["title"] as? String else { return nil }
                let url = item["url"] as? String
                let snippet = item["description"] as? String
                return SearchResult(title: title, url: url, snippet: snippet)
            }
        }
        // Fallback: parse MCP content directly (for older data or non-normalized results)
        else if let contentArray = toolData?["content"] as? [[String: Any]] {
            results = contentArray.flatMap { contentItem -> [SearchResult] in
                guard let textValue = contentItem["text"] as? String,
                      let data = textValue.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return []
                }
                // Extract results - could be array or single object
                return Self.extractResultsFromJSON(json)
            }
        }
        self.searchResults = results
        self.resultsCount = results?.count
    }

    mutating func update(from metadata: [String: Any]) {
        let toolActivity = metadata.dictionary(for: "tool_activity")
        if let newStatus = toolActivity?.string(for: "status") {
            self.status = ToolStatus(from: newStatus)
        }
        // Results are typically set once and don't update
    }
    
    func createView(actions: ChatCellActions) -> AnyView {
        AnyView(SearchCell(tool: self))
    }
    
    // MARK: - Factory for different search tools
    
    /// Check if a tool name represents a search tool
    static func isSearchTool(_ toolName: String) -> Bool {
        return toolName.contains("search") || toolName == "brave_web_search"
    }
    
    /// Create search tool for any search tool
    static func createForTool(_ toolName: String, id: String, metadata: [String: Any]) -> SearchTool? {
        guard isSearchTool(toolName) else { return nil }
        return SearchTool(id: id, metadata: metadata)
    }

    // MARK: - Smart JSON Extraction

    /// Extract search results from any JSON structure (handles various MCP formats)
    private static func extractResultsFromJSON(_ json: [String: Any]) -> [SearchResult] {
        // Try to find results array or object
        let resultKeys = ["results", "items", "data", "records", "entries", "tracks", "albums", "artists", "pages"]

        for key in resultKeys {
            if let array = json[key] as? [[String: Any]] {
                // Array of results
                return array.compactMap { normalizeItem($0) }
            } else if let obj = json[key] as? [String: Any], !obj.isEmpty {
                // Single result object (e.g., Zapier filtered output)
                if let result = normalizeItem(obj) {
                    return [result]
                }
            }
        }

        // If no nested results, try to normalize the root object
        if let result = normalizeItem(json) {
            return [result]
        }

        return []
    }

    /// Normalize a single item to SearchResult by finding common field patterns
    private static func normalizeItem(_ item: [String: Any]) -> SearchResult? {
        // Try multiple title fields
        let titleKeys = ["name", "title", "subject", "summary", "label", "display_name", "headline",
                        "album_name", "track_name", "playlist_name", "artist_name", "song_name", "event_name"]
        var title: String?
        for key in titleKeys {
            if let value = item[key] as? String, !value.isEmpty {
                title = value
                break
            }
        }

        guard let foundTitle = title else { return nil }

        // Try multiple URL fields
        let urlKeys = ["url", "href", "link", "uri", "web_url", "html_url", "htmlLink", "permalink"]
        var url: String?
        for key in urlKeys {
            if let value = item[key] as? String, value.hasPrefix("http") {
                url = value
                break
            }
        }
        // Try nested external_urls (Spotify style)
        if url == nil, let externalUrls = item["external_urls"] as? [String: Any] {
            for (_, value) in externalUrls {
                if let urlValue = value as? String, urlValue.hasPrefix("http") {
                    url = urlValue
                    break
                }
            }
        }

        // Try multiple description fields, or build from artist/author
        let descKeys = ["description", "snippet", "summary", "text", "body", "abstract"]
        var description: String?
        for key in descKeys {
            if let value = item[key] as? String, !value.isEmpty {
                description = value
                break
            }
        }
        // Build description from artist/author if not found
        if description == nil {
            if let artists = item["artists"] as? [[String: Any]], let artistName = artists.first?["name"] as? String {
                description = artistName
            } else if let artist = item["artist"] as? String {
                description = artist
            } else if let author = item["author"] as? String {
                description = author
            } else if let type = item["type"] as? String {
                description = type.capitalized
            }
        }

        return SearchResult(title: foundTitle, url: url, snippet: description)
    }
}

// MARK: - Search Result Model

struct SearchResult: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let url: String?
    let snippet: String?
}

// MARK: - Search Cell

struct SearchCell: View {
    let tool: SearchTool
    @State private var isExpanded = false

    private var isSearching: Bool {
        tool.status == .inProgress
    }

    private var resultCount: Int {
        tool.searchResults?.count ?? tool.resultsCount ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - entire row is tappable
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.foreground["300"])

                Text(tool.searchQuery ?? "Searching...")
                    .body()
                    .foregroundStyle(Color.foreground["300"])
                    .lineLimit(isExpanded ? nil : 1)
                    .shimmer(isActive: isSearching)

                Spacer(minLength: 0)

                // Show result count and chevron when done
                if !isSearching && resultCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(resultCount)")
                            .caption()
                            .foregroundStyle(Color.foreground["300"])

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.foreground["300"])
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    }
                } else if case .failure = tool.status {
                    Text("Failed")
                        .captionSmall()
                        .foregroundStyle(Color.semantic["error"])
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.semantic["error"].opacity(0.1))
                        .clipShape(Capsule())
                        .padding(.top, -2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isSearching && resultCount > 0 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            // Expanded results
            if isExpanded, let results = tool.searchResults, !results.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { result in
                            SearchResultRow(result: result)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(isExpanded ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.border["000"], lineWidth: isExpanded ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult

    private var faviconURL: URL? {
        guard let urlString = result.url,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Favicon
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                case .failure, .empty:
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.foreground["300"])
                        .frame(width: 16, height: 16)
                @unknown default:
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.foreground["300"])
                        .frame(width: 16, height: 16)
                }
            }

            Text(result.title)
                .caption()
                .foregroundStyle(Color.foreground["200"])
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview Helpers

extension SearchTool {
    /// Preview-only initializer for creating mock tools
    fileprivate init(
        id: String = UUID().uuidString,
        status: ToolStatus,
        searchQuery: String?,
        searchResults: [SearchResult]?
    ) {
        self.id = id
        self.status = status
        self.searchQuery = searchQuery
        self.searchResults = searchResults
        self.resultsCount = searchResults?.count
    }
}

// MARK: - Previews

#Preview("Searching") {
    SearchCell(tool: SearchTool(
        status: .inProgress,
        searchQuery: "best practices for SwiftUI animations",
        searchResults: nil
    ))
    .padding()
    .background(Color.background["100"])
}

#Preview("Success - Collapsed") {
    SearchCell(tool: SearchTool(
        status: .success,
        searchQuery: "SwiftUI shimmer effect tutorial",
        searchResults: [
            SearchResult(title: "How to create a shimmer effect in SwiftUI", url: "https://www.hackingwithswift.com/shimmer", snippet: nil),
            SearchResult(title: "SwiftUI Animations Guide", url: "https://developer.apple.com/tutorials/swiftui", snippet: nil),
            SearchResult(title: "Building loading states with shimmer", url: "https://medium.com/@example/shimmer", snippet: nil),
        ]
    ))
    .padding()
    .background(Color.background["100"])
}

#Preview("Success - Expanded") {
    SearchCell(tool: SearchTool(
        status: .success,
        searchQuery: "iOS development resources",
        searchResults: [
            SearchResult(title: "Apple Developer Documentation", url: "https://developer.apple.com/documentation", snippet: nil),
            SearchResult(title: "Swift.org - The Swift Programming Language", url: "https://swift.org", snippet: nil),
            SearchResult(title: "Hacking with Swift", url: "https://www.hackingwithswift.com", snippet: nil),
            SearchResult(title: "Ray Wenderlich Tutorials", url: "https://www.raywenderlich.com", snippet: nil),
            SearchResult(title: "Stack Overflow - iOS", url: "https://stackoverflow.com/questions/tagged/ios", snippet: nil),
            SearchResult(title: "NSHipster", url: "https://nshipster.com", snippet: nil),
            SearchResult(title: "Swift by Sundell", url: "https://swiftbysundell.com", snippet: nil),
            SearchResult(title: "iOS Dev Weekly", url: "https://iosdevweekly.com", snippet: nil),
            SearchResult(title: "objc.io", url: "https://objc.io", snippet: nil),
            SearchResult(title: "Point-Free", url: "https://pointfree.co", snippet: nil),
        ]
    ))
    .padding()
    .background(Color.background["100"])
}

#Preview("Failed") {
    SearchCell(tool: SearchTool(
        status: .failure("Network error"),
        searchQuery: "something that failed",
        searchResults: nil
    ))
    .padding()
    .background(Color.background["100"])
}

#Preview("All States") {
    VStack(spacing: 16) {
        SearchCell(tool: SearchTool(
            status: .inProgress,
            searchQuery: "searching for something...",
            searchResults: nil
        ))

        SearchCell(tool: SearchTool(
            status: .success,
            searchQuery: "SwiftUI tutorials",
            searchResults: [
                SearchResult(title: "Apple Developer", url: "https://developer.apple.com", snippet: nil),
                SearchResult(title: "Hacking with Swift", url: "https://hackingwithswift.com", snippet: nil),
                SearchResult(title: "Swift by Sundell", url: "https://swiftbysundell.com", snippet: nil),
            ]
        ))

        SearchCell(tool: SearchTool(
            status: .failure("Request timed out"),
            searchQuery: "failed search query",
            searchResults: nil
        ))
    }
    .padding()
    .background(Color.background["100"])
}
