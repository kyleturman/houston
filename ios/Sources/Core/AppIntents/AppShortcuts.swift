import AppIntents

@available(iOS 16.0, *)
struct HoustonAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            // Add Note Intent
            AppShortcut(
                intent: AddNoteIntent(),
                phrases: [
                    "Add a note in \(.applicationName)",
                    "Create a note in \(.applicationName)",
                    "Quick note in \(.applicationName)",
                    "Save to \(.applicationName)"
                ],
                shortTitle: "Add Note",
                systemImageName: "note.text"
            ),

            // Send Agent Query Intent (Fire-and-forget)
            AppShortcut(
                intent: SendAgentQueryIntent(),
                phrases: [
                    "Ask my \(.applicationName) agent",
                    "Query \(.applicationName)",
                    "Ask \(.applicationName)",
                    "Tell my \(.applicationName) agent"
                ],
                shortTitle: "Ask Agent",
                systemImageName: "brain"
            )
        ]
    }
}
