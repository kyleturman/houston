import SwiftUI

struct DiscoveryCard: View {
    let discovery: DiscoveryData

    /// Extract domain from URL for display
    private var domain: String? {
        guard let url = URL(string: discovery.url),
              let host = url.host else { return nil }
        // Remove www. prefix if present
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Check if this is a video link (YouTube, Vimeo, etc.)
    private var isVideo: Bool {
        let url = discovery.url.lowercased()
        return url.contains("youtube.com/watch") ||
               url.contains("youtu.be/") ||
               url.contains("vimeo.com/")
    }

    var body: some View {
        Link(destination: URL(string: discovery.url)!) {
            VStack(alignment: .leading, spacing: -40) {
                // OG Image (if available)
                if let ogImageUrl = discovery.ogImage, let imageUrl = URL(string: ogImageUrl) {
                    ZStack {
                        // Container with fixed height clips the .fill image to prevent overflow
                        GeometryReader { geometry in
                            AsyncImage(url: imageUrl) { phase in
                                switch phase {
                                case .success(let img):
                                    img
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geometry.size.width, height: 140)
                                case .failure:
                                    // Show placeholder on failure
                                    Rectangle()
                                        .fill(Color.background["200"])
                                        .frame(width: geometry.size.width, height: 140)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 32))
                                                .foregroundColor(Color.foreground["400"])
                                        )
                                case .empty:
                                    // Loading state
                                    Rectangle()
                                        .fill(Color.background["200"])
                                        .frame(width: geometry.size.width, height: 140)
                                        .overlay(
                                            ProgressView()
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        .frame(height: 140)
                        .clipped()

                        // Play button overlay for videos
                        if isVideo {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .offset(x: 2) // Visually center the play icon
                                )
                                .padding(.bottom, 32)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .clear, location: 0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(0.8)
                    .padding(.top, 9)
                    .padding(.horizontal, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(discovery.title)
                        .titleSmall()
                        .foregroundColor(Color.foreground["100"])
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Summary
                    Text(discovery.summary)
                        .body()
                        .foregroundColor(Color.foreground["200"])
                        .multilineTextAlignment(.leading)

                    // Domain at the bottom
                    if let domain = domain {
                        Text(domain)
                            .bodySmall()
                            .foregroundColor(Color.foreground["400"])
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.border["000"], lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
