import SwiftUI
import SwiftUINavigationTransitions

/// Modifier that conditionally applies matchedTransitionSource when namespace is available
private struct NoteTransitionSourceModifier: ViewModifier {
    let noteTransition: Namespace.ID?
    let sourceID: String

    func body(content: Content) -> some View {
        if let namespace = noteTransition {
            content.matchedTransitionSource(id: sourceID, in: namespace)
        } else {
            content
        }
    }
}

struct ReflectionCard: View {
    let reflection: ReflectionData
    let goal: Goal?
    let noteTransition: Namespace.ID?
    let sourceID: String
    let onAddNote: (() -> Void)?

    init(reflection: ReflectionData, goal: Goal? = nil, noteTransition: Namespace.ID? = nil, sourceID: String = "noteComposeReflection", onAddNote: (() -> Void)? = nil) {
        self.reflection = reflection
        self.goal = goal
        self.noteTransition = noteTransition
        self.sourceID = sourceID
        self.onAddNote = onAddNote
    }

    /// Accent color based on goal, falls back to warning yellow if no goal
    private var accentColor: Color {
        if goal != nil {
            return Color.accent(goal)
        }
        return Color.semantic["warning"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)

                // Show goal title if available
                if let goalTitle = goal?.title {
                    Text(goalTitle)
                        .caption()
                        .foregroundColor(accentColor)
                }

                Spacer()
            }

            // Reflection prompt
            Text(reflection.prompt)
                .body()
                .foregroundColor(Color.foreground["000"])
                .fixedSize(horizontal: false, vertical: true)

            // Add note button
            if let onAddNote = onAddNote {
                Button {
                    onAddNote()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                        Text("Add note")
                            .caption()
                    }
                    .foregroundColor(Color.foreground["000"])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(accentColor.opacity(0.15))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .modifier(NoteTransitionSourceModifier(noteTransition: noteTransition, sourceID: sourceID))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.background["100"])
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}
