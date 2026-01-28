import SwiftUI

struct NoteDetailSheetView: View {
    let noteId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) var sessionManager
    @State private var note: Note?

    init(noteId: String) {
        self.noteId = noteId
    }

    var body: some View {
        ZStack {
            // Blank background
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let displayNote = note {

                        // Title if available
                        if let title = displayNote.title, !title.isEmpty {
                            Text(title)
                                .titleLarge()
                                .foregroundColor(Color.foreground["000"])
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 40)
                                .padding(.bottom, 16)
                        }

                        // Main content with markdown styling
                        if let content = displayNote.content {
                            MarkdownText(content)
                                .foregroundColor(Color.foreground["000"])
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, displayNote.title == nil ? 40 : 0)
                        }

                        // Image carousel (if images exist)
                        if let images = displayNote.images, !images.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(images, id: \.url) { image in
                                        AsyncImage(url: URL(string: image.url)) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 200, height: 150)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            case .failure:
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.background["200"])
                                                    .frame(width: 200, height: 150)
                                                    .overlay(
                                                        Image(systemName: "photo")
                                                            .foregroundColor(Color.foreground["300"])
                                                    )
                                            case .empty:
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color.background["200"])
                                                    .frame(width: 200, height: 150)
                                                    .overlay(
                                                        ProgressView()
                                                    )
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.top, 20)
                        }

                        // Web summary (if available)
                        if let webSummary = displayNote.webSummary, !webSummary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()
                                    .background(Color.border["000"])

                                Text("WEB SUMMARY")
                                    .caption()
                                    .foregroundColor(Color.foreground["300"])

                                MarkdownText(webSummary)
                                    .font(.bodyLarge)
                                    .foregroundColor(Color.foreground["000"])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }

                        Spacer(minLength: 40)

                        // Author and metadata at bottom
                        VStack(alignment: .leading, spacing: 8) {

                            HStack(spacing: 12) {
                                Text(displayNote.source.display)
                                    .caption()
                                    .foregroundStyle(.secondary)

                                if let when = displayNote.createdAt {
                                    Text("•")
                                        .caption()
                                        .foregroundStyle(.secondary)
                                    Text(when, format: .dateTime.day().month().year().hour().minute())
                                        .caption()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        Spacer(minLength: 40)
                    }
                }
            }
        }
        // Tap anywhere to dismiss (but not on interactive elements)
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
        .task {
            // Fetch note from API
            await fetchNote()
        }
    }

    private func fetchNote() async {
        guard let baseURL = sessionManager.serverURL else { return }

        let client = APIClient(
            baseURL: baseURL,
            deviceTokenProvider: { sessionManager.deviceToken },
            userTokenProvider: { sessionManager.userToken }
        )

        do {
            let noteResource = try await client.getNote(id: noteId)
            note = Note.from(resource: noteResource)
        } catch {
            // Failed to fetch, keep using initial note if available
        }
    }
}
