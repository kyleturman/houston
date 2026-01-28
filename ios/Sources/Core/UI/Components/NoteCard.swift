import SwiftUI

struct NoteCard: View {
    let note: Note
    let accentColor: Color
    let goal: Goal? // Optional: show goal name when provided (e.g., in home feed)
    
    init(note: Note, accentColor: Color, goal: Goal? = nil) {
        self.note = note
        self.accentColor = accentColor
        self.goal = goal
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Left border
            Rectangle()
                .fill(note.source == .user ? accentColor : Color.foreground["500"])
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                // Preview image (OG image for link notes, first content image for others)
                if let previewImage = displayPreviewImage {
                    // Container with fixed height clips the .fill image to prevent overflow
                    GeometryReader { geometry in
                        AsyncImage(url: URL(string: previewImage.url)) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: 120)
                            case .failure:
                                Rectangle()
                                    .fill(Color.background["200"])
                                    .frame(width: geometry.size.width, height: 120)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(Color.foreground["300"])
                                    )
                            case .empty:
                                Rectangle()
                                    .fill(Color.background["200"])
                                    .frame(width: geometry.size.width, height: 120)
                                    .overlay(
                                        ProgressView()
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Processing state for URL notes
                if let processingState = note.processingState {
                    processingStateView(state: processingState)
                }

                // Link note layout (simple: just title and metadata)
                if isLinkNote {
                    // Title (required for link notes)
                    if let title = note.title {
                        Text(title)
                            .titleSmall()
                            .foregroundColor(Color.foreground["000"])
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }

                    // Domain from source URL
                    if let domain = extractDomain(from: note.sourceURL) {
                        Text(domain)
                            .body()
                            .foregroundColor(Color.foreground["300"])
                    }

                    // Time and source pill
                    HStack(spacing: 6) {
                        if note.source == .user {
                            Text("YOU")
                                .captionSmall()
                                .foregroundColor(Color.foreground["000"])
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor)
                                .clipShape(Capsule())
                        }

                        if let when = note.createdAt {
                            Text(simpleRelativeTime(from: when))
                                .body()
                                .foregroundColor(Color.foreground["300"])
                        }

                        Spacer()
                    }
                } else {
                    // Regular note layout (full content display)
                    // Header: Title and time/pill (only show if title exists)
                    if note.title != nil {
                        HStack(alignment: .top) {
                            Text(note.title!)
                                .titleSmall()
                                .foregroundColor(Color.foreground["100"])

                            Spacer()

                            HStack(spacing: 6) {
                                if note.source == .user {
                                    Text("YOU")
                                        .captionSmall()
                                        .foregroundColor(Color.foreground["000"])
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(accentColor)
                                        .clipShape(Capsule())
                                }

                                if let when = note.createdAt {
                                    Text(simpleRelativeTime(from: when))
                                        .body()
                                        .foregroundColor(Color.foreground["300"])
                                }
                            }
                        }
                    }

                    // Body text - when no title, use larger font and more lines
                    if note.title == nil {
                        // No title - show content with larger font and time/pill inline
                        VStack(alignment: .leading, spacing: 8) {
                            if let content = note.content, !content.isEmpty {
                                Text(MarkdownUtils.toPlainText(content))
                                    .bodyLarge()
                                    .foregroundColor(Color.foreground["000"])
                                    .lineLimit(4)
                                    .truncationMode(.tail)
                            }

                            HStack(spacing: 6) {
                                if note.source == .user {
                                    Text("YOU")
                                        .captionSmall()
                                        .foregroundColor(Color.foreground["000"])
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(accentColor)
                                        .clipShape(Capsule())
                                }

                                if let when = note.createdAt {
                                    Text(simpleRelativeTime(from: when))
                                        .body()
                                        .foregroundColor(Color.foreground["300"])
                                }

                                Spacer()
                            }
                        }
                    } else {
                        // Has title - show content as secondary text
                        if let content = note.content, !content.isEmpty {
                            Text(MarkdownUtils.toPlainText(content))
                                .body()
                                .foregroundColor(Color.foreground["400"])
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }

                        // Show web summary if available
                        if let webSummary = note.webSummary, !webSummary.isEmpty {
                            Divider()
                                .background(Color.border["000"])
                                .padding(.vertical, 8)

                            MarkdownText(webSummary)
                                .font(.body)
                                .foregroundColor(Color.foreground["400"])
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }
                    }
                }

                // Goal name at bottom (if provided - for home feed context)
                if let goal = goal {
                    Text(goal.title)
                        .caption()
                        .foregroundColor(accentColor)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Determines if this note is a link note (has sourceURL)
    private var isLinkNote: Bool {
        note.sourceURL != nil
    }

    /// Image to display in card preview
    /// For link notes: uses OG image
    /// For regular notes: uses first content image
    private var displayPreviewImage: NoteImage? {
        if isLinkNote {
            return note.ogImage
        } else {
            return note.images?.first
        }
    }

    /// Extracts domain from URL, removing www prefix
    /// - Parameter urlString: The source URL string
    /// - Returns: Clean domain (e.g., "github.com") or nil if invalid
    private func extractDomain(from urlString: String?) -> String? {
        guard let urlString = urlString,
              let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }

        // Remove www. prefix if present
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }

        return host
    }

    @ViewBuilder
    private func processingStateView(state: String) -> some View {
        switch state {
        case "pending":
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Summarizing web content...")
                    .caption()
                    .foregroundColor(Color.foreground["300"])
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.background["200"])
            .cornerRadius(8)

        case "failed":
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                    Text("Failed to summarize web content")
                        .caption()
                }
                .foregroundColor(Color.foreground["300"])

                HStack(spacing: 12) {
                    Button("Retry") {
                        // TODO: Implement retry action
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Ignore") {
                        // TODO: Implement ignore action
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.background["200"])
            .cornerRadius(8)

        default:
            EmptyView()
        }
    }

    private func extractTitle(from content: String) -> String {
        // Extract title from content - use first line or first heading
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard let firstLine = lines.first else { return "Note" }

        var title = String(firstLine)
        // Remove markdown heading markers
        title = title.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        // Remove bold/italic markers
        title = title.replacingOccurrences(of: "[*_]", with: "", options: .regularExpression)
        // Trim
        title = title.trimmingCharacters(in: .whitespaces)
        
        return title.isEmpty ? "Note" : title
    }
    
    
    private func simpleRelativeTime(from date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)
        let minutes = Int(seconds / 60)
        let hours = Int(seconds / 3600)
        let days = Int(seconds / 86400)
        let weeks = Int(days / 7)
        let months = Int(days / 30)
        let years = Int(days / 365)
        
        if years > 0 {
            return "\(years)y"
        } else if months > 0 {
            return "\(months)mo"
        } else if weeks > 0 {
            return "\(weeks)w"
        } else if days > 0 {
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "now"
        }
    }
}
