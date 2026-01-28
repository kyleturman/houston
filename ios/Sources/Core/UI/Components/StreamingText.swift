import SwiftUI

/// A text view that smoothly animates streaming content with inline markdown support.
/// Parses simple markdown (bold, italic) and renders with per-word fade-in animation.
struct StreamingText: View {
    /// The full content to display (updated as chunks arrive)
    let content: String

    /// Whether content is still streaming
    let isStreaming: Bool

    /// Words revealed per animation tick
    private let wordsPerTick: Int = 2

    /// Time between animation ticks (fast and snappy)
    private let tickInterval: TimeInterval = 0.075

    /// Duration for each word's fade-in animation
    private let fadeInDuration: TimeInterval = 0.4

    /// Current number of tokens fully visible (done animating)
    @State private var stableTokenCount: Int = 0

    /// Current number of tokens being displayed (includes animating ones)
    @State private var displayedTokenCount: Int = 0

    /// Opacity for the currently animating tokens
    @State private var newTokensOpacity: Double = 1.0

    /// Timer for progressive reveal
    @State private var revealTimer: Timer?

    /// A token is a word with its associated style
    private struct StyledToken {
        let text: String
        let isBold: Bool
        let isItalic: Bool
        let isWhitespace: Bool
    }

    /// Parse content into styled tokens
    private var tokens: [StyledToken] {
        parseMarkdown(content)
    }

    /// Tokens that are fully visible (opacity = 1, no animation)
    private var stableTokens: [StyledToken] {
        Array(tokens.prefix(stableTokenCount))
    }

    /// Tokens that are currently fading in
    private var animatingTokens: [StyledToken] {
        if displayedTokenCount > stableTokenCount {
            return Array(tokens[stableTokenCount..<min(displayedTokenCount, tokens.count)])
        }
        return []
    }

    var body: some View {
        styledTextView
            .onChange(of: content) { _, _ in
                if isStreaming {
                    startRevealAnimation()
                }
            }
            .onChange(of: isStreaming) { _, newValue in
                if !newValue {
                    // Streaming ended - show all tokens immediately
                    stopRevealAnimation()
                    stableTokenCount = tokens.count
                    displayedTokenCount = tokens.count
                    newTokensOpacity = 1.0
                }
            }
            .onAppear {
                if isStreaming && !content.isEmpty {
                    startRevealAnimation()
                } else if !isStreaming {
                    // Not streaming - show all content immediately
                    stableTokenCount = tokens.count
                    displayedTokenCount = tokens.count
                    newTokensOpacity = 1.0
                }
            }
            .onDisappear {
                stopRevealAnimation()
            }
    }

    /// Render styled text with per-token opacity
    private var styledTextView: some View {
        // Build stable text (full opacity)
        let stableText = stableTokens.reduce(Text("")) { result, token in
            result + styledText(for: token, opacity: 1.0)
        }

        // Build animating text (fading in)
        let animatingText = animatingTokens.reduce(Text("")) { result, token in
            result + styledText(for: token, opacity: newTokensOpacity)
        }

        return (stableText + animatingText)
            .font(.custom(AppFontFamily, size: 13))
            .foregroundColor(Color.foreground["100"])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(3)
    }

    /// Create styled Text for a token
    private func styledText(for token: StyledToken, opacity: Double) -> Text {
        var text = Text(token.text)

        if token.isBold {
            text = text.bold()
        }
        if token.isItalic {
            text = text.italic()
        }

        // Apply opacity via foreground color
        return text.foregroundColor(Color.foreground["100"].opacity(opacity))
    }

    /// Parse simple markdown into styled tokens
    /// Supports: **bold**, *italic*, __bold__, _italic_
    private func parseMarkdown(_ input: String) -> [StyledToken] {
        var tokens: [StyledToken] = []
        var remaining = input
        var isBold = false
        var isItalic = false

        while !remaining.isEmpty {
            // Check for markdown markers at current position
            if remaining.hasPrefix("**") || remaining.hasPrefix("__") {
                remaining.removeFirst(2)
                isBold.toggle()
                continue
            }

            if remaining.hasPrefix("*") || remaining.hasPrefix("_") {
                // Check it's not part of ** or __
                let nextChar = remaining.dropFirst().first
                if nextChar != "*" && nextChar != "_" {
                    remaining.removeFirst()
                    isItalic.toggle()
                    continue
                }
            }

            // Extract next word WITH its trailing whitespace
            // This keeps rendering consistent vs separate whitespace tokens
            let char = remaining.first!

            if char.isWhitespace || char.isNewline {
                // Leading whitespace before any word - collect it
                var whitespace = ""
                while let c = remaining.first, c.isWhitespace || c.isNewline {
                    whitespace.append(c)
                    remaining.removeFirst()
                }
                tokens.append(StyledToken(
                    text: whitespace,
                    isBold: isBold,
                    isItalic: isItalic,
                    isWhitespace: true
                ))
            } else {
                // Collect word characters until whitespace or markdown marker
                var word = ""
                while let c = remaining.first,
                      !c.isWhitespace && !c.isNewline &&
                      !remaining.hasPrefix("**") && !remaining.hasPrefix("__") &&
                      !remaining.hasPrefix("*") && !remaining.hasPrefix("_") {
                    word.append(c)
                    remaining.removeFirst()
                }
                // Include trailing whitespace with this word (but not newlines - those affect layout)
                while let c = remaining.first, c == " " || c == "\t" {
                    word.append(c)
                    remaining.removeFirst()
                }
                if !word.isEmpty {
                    tokens.append(StyledToken(
                        text: word,
                        isBold: isBold,
                        isItalic: isItalic,
                        isWhitespace: false
                    ))
                }
            }
        }

        return tokens
    }

    private func startRevealAnimation() {
        guard displayedTokenCount < tokens.count else { return }
        guard revealTimer == nil else { return }

        revealTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [self] _ in
            DispatchQueue.main.async {
                let totalTokens = tokens.count
                if displayedTokenCount < totalTokens {
                    // Mark current animating tokens as stable
                    stableTokenCount = displayedTokenCount

                    // Start fading in new tokens
                    newTokensOpacity = 0
                    displayedTokenCount = min(displayedTokenCount + wordsPerTick, totalTokens)

                    // Animate opacity to 1
                    withAnimation(.easeOut(duration: fadeInDuration)) {
                        newTokensOpacity = 1.0
                    }
                } else {
                    // All tokens revealed, mark as stable and stop
                    stableTokenCount = displayedTokenCount
                    stopRevealAnimation()
                }
            }
        }
    }

    private func stopRevealAnimation() {
        revealTimer?.invalidate()
        revealTimer = nil
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        StreamingText(
            content: "Hello! This is a **bold** message with *italic* support.",
            isStreaming: true
        )

        StreamingText(
            content: "Regular text, then **bold text**, then *italic*, then **bold *and italic***.",
            isStreaming: false
        )
    }
    .padding()
}
