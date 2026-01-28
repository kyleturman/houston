import SwiftUI

struct GoalSettingsSheet: View {
    let goal: Goal
    @Environment(\.dismiss) var dismiss
    @Environment(SessionManager.self) var session
    @Environment(ThemeManager.self) var themeManager
    
    @State private var title: String
    @State private var description: String
    @State private var agentInstructions: String
    @State private var enabledMcpServers: [String]
    @State private var accentColor: String?
    @State private var showAgentInstructions = false
    @State private var showingColorPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    init(goal: Goal) {
        self.goal = goal
        _title = State(initialValue: goal.title)
        _description = State(initialValue: goal.description ?? "")
        _agentInstructions = State(initialValue: goal.agentInstructions ?? "")
        _enabledMcpServers = State(initialValue: goal.enabledMcpServers ?? [])
        _accentColor = State(initialValue: goal.accentColor)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                MCPServerSelectionSection(enabledMcpServers: $enabledMcpServers)

                AgentInstructionsSection(agentInstructions: $agentInstructions, isExpanded: $showAgentInstructions)

                AccentColorPickerButton(selectedColor: $accentColor, showingPicker: $showingColorPicker)

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(Color.semantic["error"])
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showingColorPicker) {
                AccentColorPickerSheet(selectedColor: $accentColor)
                    .presentationDetents([.medium])
            }
        }
    }
    
    private func saveGoal() {
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            guard let base = session.serverURL else {
                isSaving = false
                errorMessage = "Missing server configuration"
                return
            }

            // Capture token values before creating client
            let deviceToken = session.deviceToken
            let userToken = session.userToken

            let result = await SaveCoordinator.blockingSave(
                loadingMessage: "Saving goal...",
                successMessage: "Goal updated"
            ) {
                let client = APIClient(
                    baseURL: base,
                    deviceTokenProvider: { deviceToken },
                    userTokenProvider: { userToken }
                )

                let trimmedTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = self.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedInstructions = self.agentInstructions.trimmingCharacters(in: .whitespacesAndNewlines)

                return try await client.updateGoal(
                    id: self.goal.id,
                    title: trimmedTitle,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    status: self.goal.status.rawValue,
                    agentInstructions: trimmedInstructions.isEmpty ? nil : trimmedInstructions,
                    enabledMcpServers: self.enabledMcpServers,
                    accentColor: self.accentColor
                )
            }

            isSaving = false

            // On success, dismiss. On failure, keep sheet open to show error
            if case .success = result {
                dismiss()
            } else if case .failure(let error) = result {
                errorMessage = error
            }
        }
    }
}
