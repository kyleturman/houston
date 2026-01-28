import SwiftUI
import MarkdownUI

struct MarkdownText: View {
    let content: String
    
    init(_ content: String) {
        self.content = content
    }
    
    var body: some View {
        Markdown(content)
            .markdownTextStyle {
                FontFamily(.custom(AppFontFamily))
                FontSize(13)  // Matches body() font size
                ForegroundColor(.primary)
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(13)  // Matches body() font size
                    }
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: .zero, bottom: .em(1.25))
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownTextStyle {
                        FontFamily(.custom(AppTitleFontFamily))
                        FontWeight(.semibold)
                        FontSize(17)  // Matches title() font size
                    }
                    .markdownMargin(top: .em(0.8), bottom: .em(0.5))
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownTextStyle {
                        FontFamily(.custom(AppTitleFontFamily))
                        FontWeight(.semibold)
                        FontSize(15)  // Matches titleSmall() font size
                    }
                    .markdownMargin(top: .em(0.8), bottom: .em(0.5))
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(13)  // Matches body() font size
                    }
                    .markdownMargin(top: .em(0.25))
            }
    }
}
